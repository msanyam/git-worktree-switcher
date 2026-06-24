#!/usr/bin/env zsh
_CDW_PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"

_cdw_check_fzf() {
    if ! PATH="$_CDW_PATH" command -v fzf &>/dev/null; then
        echo "cdw: fzf not found"
        return 1
    fi
}

_cdw_check_git() {
    if ! PATH="$_CDW_PATH" git rev-parse --is-inside-work-tree &>/dev/null; then
        echo "cdw: not a git repository"
        return 1
    fi
}

_cdw_read_rc_key() {
    local config="$HOME/.cdwrc" key="$1"
    [[ ! -f $config ]] && return 1
    local line
    line=$(PATH="$_CDW_PATH" grep -m1 "^${key}=" "$config") || return 1
    print -r -- "${line#*=}"
}

_cdw_run_hook() {
    local hook_name=$1 hook_cmd=$2 branch=$3 worktree_path=$4
    [[ -z $hook_cmd ]] && return 0
    local rc
    if [[ -n $branch ]]; then
        CDW_BRANCH="$branch" CDW_WORKTREE_PATH="$worktree_path" eval "$hook_cmd"
    else
        CDW_WORKTREE_PATH="$worktree_path" eval "$hook_cmd"
    fi
    rc=$?
    (( rc != 0 )) && echo "cdw: ${hook_name} hook failed (exit $rc)"
    return 0
}

_cdw_cd() {
    local worktree_path=$1
    if [[ ! -d $worktree_path ]]; then
        echo "cdw: path does not exist: $worktree_path"
        return 1
    fi
    cd "$worktree_path" || return 1
    local hook_cmd
    hook_cmd=$(_cdw_read_rc_key "post_selection")
    _cdw_run_hook "post_selection" "$hook_cmd" "" "$worktree_path"
}

_cdw_confirm() {
    local prompt=$1 char
    printf '%s' "$prompt"
    read -sk 1 char
    print ''
    if [[ $char == $'\e' ]]; then
        return 2
    elif [[ $char == [yY] ]]; then
        return 0
    else
        return 1
    fi
}

_cdw_erase_lines() {
    local n=${1:-1}
    repeat $n { printf '\033[1A\r\033[2K' }
}

typeset -g _cdw_vared_escaped=0

_cdw_vared_escape_widget() {
    _cdw_vared_escaped=1
    zle .send-break
}
[[ -o zle ]] && zle -N _cdw_vared_escape_widget

_cdw_delete() {
    local worktree_path=$1 main_path=$2 branch_name=$3
    local confirms_printed=0
    if [[ $worktree_path == "$main_path" ]]; then
        echo "cdw: cannot delete the main worktree"
        return 1
    fi
    _cdw_confirm "Remove $worktree_path? [y/N] "
    local confirm_rc=$?
    (( confirms_printed++ ))
    (( confirm_rc == 2 )) && { _cdw_erase_lines $confirms_printed; return 2; }
    (( confirm_rc != 0 )) && { _cdw_erase_lines $confirms_printed; return 0; }
    if ! PATH="$_CDW_PATH" git worktree remove "$worktree_path"; then
        _cdw_confirm "Worktree has uncommitted or untracked changes. Force remove? [y/N] "
        confirm_rc=$?
        (( confirms_printed++ ))
        (( confirm_rc == 2 )) && { _cdw_erase_lines $confirms_printed; return 2; }
        (( confirm_rc != 0 )) && { _cdw_erase_lines $confirms_printed; return 0; }
        if ! PATH="$_CDW_PATH" git worktree remove --force "$worktree_path"; then
            echo "cdw: failed to force-remove worktree '$worktree_path'"
            return 1
        fi
    fi
    # Worktree dir (and its submodule checkouts) is gone — drop the now-stale
    # submodule worktree registrations left behind in .git/modules/*/worktrees/.
    _cdw_prune_submodule_worktrees "$main_path"
    [[ -z $branch_name ]] && { _cdw_erase_lines $confirms_printed; return 0; }
    local setting
    setting=$(_cdw_read_rc_key "delete_branch") || setting=ask
    [[ $setting != always && $setting != skip && $setting != ask ]] && setting=ask
    [[ $setting == skip ]] && { _cdw_erase_lines $confirms_printed; return 0; }
    if [[ $setting == ask ]]; then
        _cdw_confirm "Also delete branch '$branch_name'? [y/N] "
        local confirm_rc=$?
        (( confirms_printed++ ))
        (( confirm_rc == 2 )) && { _cdw_erase_lines $confirms_printed; return 2; }
        (( confirm_rc != 0 )) && { _cdw_erase_lines $confirms_printed; return 0; }
    fi
    if PATH="$_CDW_PATH" git -C "$main_path" branch -d "$branch_name" 2>/dev/null; then
        _cdw_erase_lines $confirms_printed
        echo "cdw: deleted branch '$branch_name'"
    else
        echo "cdw: could not delete branch '$branch_name' (not fully merged)"
        _cdw_confirm "Force delete '$branch_name'? [y/N] "
        local force_rc=$?
        (( confirms_printed++ ))
        if (( force_rc == 0 )); then
            if PATH="$_CDW_PATH" git -C "$main_path" branch -D "$branch_name" 2>/dev/null; then
                _cdw_erase_lines $confirms_printed
                echo "cdw: force-deleted branch '$branch_name'"
            else
                echo "cdw: could not force-delete branch '$branch_name'"
            fi
        else
            _cdw_erase_lines $confirms_printed
        fi
    fi
}

_cdw_cmd_init_submodules() {
    _cdw_check_git || return 1
    if [[ ! -f "${PWD}/.gitmodules" ]]; then
        echo "cdw: no submodules found"
        return 0
    fi
    echo "cdw: initializing submodule worktrees..."
    _cdw_init_submodule_worktrees "$PWD"
}

# Serialize submodule-worktree init across all worktrees and concurrent cdw
# runs of the same superproject. Without this, parallel `git worktree add`
# calls race on the auto-allocated worktrees/<name> directory and can produce
# two checkouts pointing at one gitdir (shared HEAD/index = corruption).
# Uses the zsh built-in `zsystem flock` (no external dependency; the flock(1)
# binary is absent on macOS). The lock file lives in the superproject's shared
# git dir so every worktree/session contends on the same lock. Fixed 30s
# timeout; on timeout we fail loud and never proceed unlocked. The lock is held
# only while $@ runs and released when this function returns.
_cdw_with_submodule_lock() {
    local common_dir=$1; shift
    local lockfile="${common_dir}/cdw-submodules.lock"
    if ! zmodload zsh/system 2>/dev/null; then
        echo "cdw: zsh/system module unavailable; cannot lock submodule init"
        return 1
    fi
    [[ -e $lockfile ]] || : >| "$lockfile" 2>/dev/null
    local lockfd
    if ! zsystem flock -t 30 -f lockfd "$lockfile" 2>/dev/null; then
        echo "cdw: another process is initializing submodules; try again"
        return 1
    fi
    "$@"
    local rc=$?
    zsystem flock -u "$lockfd" 2>/dev/null
    return $rc
}

# Pre-flight checks on a submodule's shared module store before we add a
# worktree against it. Returns non-zero with a one-line reason on stdout if any
# check fails. Checks: (1) the module gitdir is a healthy repo (HEAD + objects
# resolve), not a gutted directory; (2) the submodule is actually initialized in
# the main checkout (its copy resolves to itself, not the superproject); (3) the
# superproject-pinned commit exists in the local store — never fetched from a
# remote. args: <module_gitdir> <main_path> <submodule_path> <gitlink>
_cdw_validate_submodule_store() {
    local gitdir=$1 main_path=$2 sub=$3 gitlink=$4 main_top
    if ! PATH="$_CDW_PATH" git -C "$gitdir" rev-parse --git-dir &>/dev/null \
       || ! PATH="$_CDW_PATH" git -C "$gitdir" rev-parse HEAD &>/dev/null; then
        echo "module store is not a healthy git repository ($gitdir)"
        return 1
    fi
    main_top=$(PATH="$_CDW_PATH" git -C "${main_path}/${sub}" rev-parse --show-toplevel 2>/dev/null)
    if [[ $main_top != */${sub} ]]; then
        echo "submodule not initialized in the main checkout"
        return 1
    fi
    if [[ $gitlink != HEAD ]] \
       && ! PATH="$_CDW_PATH" git -C "$gitdir" cat-file -e "${gitlink}^{commit}" 2>/dev/null; then
        echo "pinned commit ${gitlink} not in local store; run 'git submodule update' in the main checkout"
        return 1
    fi
    return 0
}

# After `git worktree add`, assert the new submodule checkout's gitdir points
# back to THIS checkout. If a concurrent process grabbed the same
# worktrees/<name>, the backlink will name a different checkout — the exact
# corruption signature from the 2026-06-17 incident. Returns non-zero on
# mismatch. arg: <checkout_path> (absolute path to the submodule checkout)
_cdw_check_worktree_backlink() {
    local checkout=$1 gd backlink
    gd=$(PATH="$_CDW_PATH" git -C "$checkout" rev-parse --absolute-git-dir 2>/dev/null) || return 1
    [[ -f "${gd}/gitdir" ]] || return 1
    backlink=$(<"${gd}/gitdir")
    [[ $backlink == "${checkout}/.git" ]]
}

# Undo a partial submodule worktree add for ONE submodule, leaving the parent
# worktree and all other submodules intact. Removes the registered worktree (or
# the leftover dir) and prunes the dangling registration from the module store.
# args: <module_gitdir> <checkout_path>
_cdw_rollback_submodule() {
    local gitdir=$1 checkout=$2
    if [[ -e "${checkout}/.git" ]]; then
        PATH="$_CDW_PATH" git -C "$gitdir" worktree remove --force "$checkout" 2>/dev/null
    fi
    [[ -d $checkout ]] && rm -rf "$checkout"
    PATH="$_CDW_PATH" git -C "$gitdir" worktree prune 2>/dev/null
    return 0
}

# Enable per-worktree config on a submodule's *shared* gitdir before we ever
# run `git worktree add` against it. Without extensions.worktreeConfig, the
# per-worktree `core.worktree` that `git worktree add` writes lands in the
# shared config and clobbers the existing checkout's value — the corruption
# that produced `fatal: cannot chdir` for every linked worktree. With it on,
# git stores `core.worktree` in config.worktree (per worktree) instead, so the
# shared config is left intact. We also migrate any pre-existing shared
# core.worktree into the main worktree's config.worktree so the first checkout
# keeps working.
_cdw_enable_submodule_worktree_config() {
    local gitdir=$1
    local shared="${gitdir}/config" per_main="${gitdir}/config.worktree"
    [[ $(PATH="$_CDW_PATH" git config --file "$shared" extensions.worktreeConfig 2>/dev/null) == true ]] && return 0
    local existing
    existing=$(PATH="$_CDW_PATH" git config --file "$shared" core.worktree 2>/dev/null)
    if [[ -n $existing ]]; then
        PATH="$_CDW_PATH" git config --file "$shared" --unset core.worktree 2>/dev/null
        PATH="$_CDW_PATH" git config --file "$per_main" core.worktree "$existing" 2>/dev/null
    fi
    PATH="$_CDW_PATH" git config --file "$shared" extensions.worktreeConfig true 2>/dev/null
}

# Submodule-init run summary counters (set by the entry point, accumulated by
# the recursive worker — both run in the current shell, so globals persist).
typeset -g _cdw_sm_ok=0
typeset -ga _cdw_sm_failed=()

# Entry point: initialize a freshly created worktree's submodules as *linked
# worktrees* of the main checkout's submodule repos (shared object store + refs,
# so checkouts appear as sibling worktrees of each other). Acquires the
# superproject lock once, runs the recursive worker under it, then prints a
# summary. Local-only: never contacts a remote.
_cdw_init_submodule_worktrees() {
    local worktree_path=$1 common_dir main_path
    [[ ! -f "${worktree_path}/.gitmodules" ]] && return 0
    common_dir=$(PATH="$_CDW_PATH" git -C "$worktree_path" rev-parse --git-common-dir 2>/dev/null)
    [[ -n $common_dir && $common_dir != /* ]] && common_dir="${worktree_path}/${common_dir}"
    if [[ -z $common_dir ]]; then
        echo "cdw: could not determine git common dir; skipping submodule init"
        return 1
    fi
    main_path="${common_dir:h}"
    _cdw_sm_ok=0
    _cdw_sm_failed=()
    _cdw_with_submodule_lock "$common_dir" _cdw_add_submodule_worktrees "$worktree_path" "$main_path" 0
    local rc=$?
    local total=$(( _cdw_sm_ok + ${#_cdw_sm_failed[@]} ))
    echo "cdw: initialized ${_cdw_sm_ok} of ${total} submodules"
    (( ${#_cdw_sm_failed[@]} )) && echo "cdw: failed: ${_cdw_sm_failed[*]}"
    return $rc
}

# Recursive worker (runs INSIDE the lock). For each submodule: validate the
# shared store, enable worktreeConfig, `git worktree add --detach` at the
# pinned gitlink, assert the gitdir backlink, and on any failure roll back that
# submodule and continue. Recurses one level for nested submodules (depth cap
# 2). Detached HEAD avoids "branch already checked out in another worktree".
_cdw_add_submodule_worktrees() {
    local worktree_path=$1 main_path=$2 depth=${3:-0}
    [[ $depth -ge 2 ]] && return 0
    [[ ! -f "${worktree_path}/.gitmodules" ]] && return 0

    local common_dir submodule_path submodule_gitdir gitlink checkout err add_err
    common_dir=$(PATH="$_CDW_PATH" git -C "$worktree_path" rev-parse --git-common-dir 2>/dev/null)
    [[ -n $common_dir && $common_dir != /* ]] && common_dir="${worktree_path}/${common_dir}"

    while IFS= read -r submodule_path; do
        [[ -z $submodule_path ]] && continue
        submodule_gitdir="${common_dir}/modules/${submodule_path}"
        checkout="${worktree_path}/${submodule_path}"
        gitlink=$(PATH="$_CDW_PATH" git -C "$worktree_path" rev-parse "HEAD:${submodule_path}" 2>/dev/null)
        [[ -z $gitlink ]] && gitlink=HEAD

        if [[ -f "${checkout}/.git" ]]; then
            echo "cdw: submodule '${submodule_path}': already initialized, skipping"
            continue
        fi

        if ! err=$(_cdw_validate_submodule_store "$submodule_gitdir" "$main_path" "$submodule_path" "$gitlink"); then
            echo "cdw: submodule '${submodule_path}' failed: ${err}"
            _cdw_sm_failed+=("$submodule_path")
            continue
        fi

        _cdw_enable_submodule_worktree_config "$submodule_gitdir"

        if ! add_err=$(PATH="$_CDW_PATH" git -C "$submodule_gitdir" worktree add --detach "$checkout" "$gitlink" 2>&1); then
            echo "cdw: submodule '${submodule_path}' failed: worktree add error:"
            print -r -- "$add_err" | sed 's/^/cdw:   /'
            _cdw_rollback_submodule "$submodule_gitdir" "$checkout"
            _cdw_sm_failed+=("$submodule_path")
            continue
        fi

        if ! _cdw_check_worktree_backlink "$checkout"; then
            echo "cdw: submodule '${submodule_path}' failed: gitdir backlink mismatch (concurrent collision)"
            _cdw_rollback_submodule "$submodule_gitdir" "$checkout"
            _cdw_sm_failed+=("$submodule_path")
            continue
        fi

        (( _cdw_sm_ok++ ))
        _cdw_add_submodule_worktrees "$checkout" "${main_path}/${submodule_path}" $(( depth + 1 ))
    done < <(PATH="$_CDW_PATH" git -C "$worktree_path" config --file .gitmodules --get-regexp 'submodule\..*\.path' 2>/dev/null | awk '{print $2}')
}

# After a worktree's directory tree has been removed, its submodule checkouts
# are gone but the submodule repos still hold now-stale worktree registrations
# under .git/modules/<path>/worktrees/. Prune them so the registrations don't
# accumulate. This runs *after* the parent `git worktree remove` succeeds, so a
# cancelled/declined delete never destroys submodule working trees. `prune`
# only drops registrations whose checkout path is missing, so it's safe to run
# across every submodule gitdir under the superproject.
_cdw_prune_submodule_worktrees() {
    local main_path=$1 common_dir wt
    common_dir=$(PATH="$_CDW_PATH" git -C "$main_path" rev-parse --git-common-dir 2>/dev/null)
    [[ -n $common_dir && $common_dir != /* ]] && common_dir="${main_path}/${common_dir}"
    [[ -d "${common_dir}/modules" ]] || return 0
    for wt in "${common_dir}"/modules/**/worktrees(N/); do
        PATH="$_CDW_PATH" git -C "${wt:h}" worktree prune 2>/dev/null
    done
}

_cdw_create() {
    local main_path=$1
    local branch_name hook_cmd
    branch_name=$(_cdw_read_rc_key "branch_prefix")
    typeset -g _cdw_vared_escaped=0
    local prior_esc
    prior_esc=$(bindkey '\e' 2>/dev/null | awk '{print $2}' | grep -v '^undefined-key$')
    bindkey '\e' _cdw_vared_escape_widget
    vared -p "Branch name: " branch_name
    if [[ -n $prior_esc ]]; then
        bindkey '\e' "$prior_esc"
    else
        bindkey -r '\e'
    fi

    (( _cdw_vared_escaped )) && return 2
    [[ -z $branch_name ]] && return 0
    local derived_path="${main_path}/.worktrees/${branch_name//\//-}"
    mkdir -p "${main_path}/.worktrees"
    if ! PATH="$_CDW_PATH" git worktree add -b "$branch_name" "$derived_path"; then
        [[ -d $derived_path ]] && rmdir "$derived_path" 2>/dev/null
        echo "cdw: if '$branch_name' already exists, use: git worktree add $derived_path $branch_name"
        return 1
    fi
    if [[ -f "${derived_path}/.gitmodules" ]]; then
        echo "cdw: initializing submodule worktrees..."
        _cdw_init_submodule_worktrees "$derived_path"
    fi
    if ! cd "$derived_path"; then
        echo "cdw: could not cd into $derived_path"
        return 1
    fi
    hook_cmd=$(_cdw_read_rc_key "post_create")
    _cdw_run_hook "post_create" "$hook_cmd" "$branch_name" "$derived_path"
}

typeset -gA _cdw_handlers
_cdw_handlers=(
    bspace _cdw_delete
)

_cdw_main() {
    _cdw_check_fzf || return 1
    _cdw_check_git || return 1

    local main_path
    main_path=$(PATH="$_CDW_PATH" git worktree list 2>/dev/null | head -1 | awk '{print $1}')
    if [[ -z $main_path ]]; then
        echo "cdw: could not determine main worktree path"
        return 1
    fi

    local output key selected fzf_exit handler_rc worktree_path branch_raw branch_name
    while true; do
        [[ -o xtrace ]] && print -u2 "[cdw] WARNING: xtrace is ON at loop top"
        output=$(
            { printf '[+ new worktree]\n'; PATH="$_CDW_PATH" git worktree list; } \
            | PATH="$_CDW_PATH" fzf \
                --expect="${(kj:,:)_cdw_handlers}" \
                --header='Enter: cd/create  ⌫: delete' \
                --height=40% \
                --reverse \
                --no-info
        )
        fzf_exit=$?

        if (( fzf_exit == 1 || fzf_exit == 130 )); then
            return 0
        elif (( fzf_exit != 0 )); then
            echo "cdw: fzf exited with error (code $fzf_exit)"
            return 1
        fi

        key=$(head -1 <<< "$output")
        selected=$(tail -1 <<< "$output")

        [[ -z $selected || $selected == "$key" ]] && return 0

        handler_rc=0

        if [[ $selected == '[+ new worktree]' ]]; then
            [[ $key == 'bspace' ]] && return 0
            _cdw_create "$main_path"
            handler_rc=$?
        else
            worktree_path=$(awk '{print $1}' <<< "$selected")

            branch_raw=$(awk '{print $3}' <<< "$selected")
            if [[ $branch_raw == \(* || -z $branch_raw ]]; then
                branch_name=''
            else
                branch_name=${branch_raw//[\[\]]/}
            fi

            if [[ -z $key ]]; then
                _cdw_cd "$worktree_path"
                handler_rc=$?
            elif (( ${+_cdw_handlers[$key]} )); then
                ${_cdw_handlers[$key]} "$worktree_path" "$main_path" "$branch_name"
                handler_rc=$?
            fi
        fi

        (( handler_rc == 2 )) && continue
        return $handler_rc
    done
}

cdw() {
    if [[ $1 == init-submodules ]]; then
        _cdw_cmd_init_submodules
        return $?
    fi
    local _cdw_xt=0
    [[ -o xtrace ]] && _cdw_xt=1 && set +x
    _cdw_main "$@"
    local rc=$?
    (( _cdw_xt )) && set -x
    return $rc
}

