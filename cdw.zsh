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
    local config="$1/.cdwrc" key="$2"
    [[ ! -f $config ]] && return 1
    local line
    line=$(PATH="$_CDW_PATH" grep -m1 "^${key}=" "$config") || return 1
    print -r -- "${line#*=}"
}

_cdw_run_hook() {
    local hook_cmd=$1 branch=$2 worktree_path=$3
    [[ -z $hook_cmd ]] && return 0
    local rc
    CDW_BRANCH="$branch" CDW_WORKTREE_PATH="$worktree_path" eval "$hook_cmd"
    rc=$?
    if (( rc != 0 )); then
        echo "cdw: post_create hook failed (exit $rc)"
    fi
}

_cdw_cd() {
    local worktree_path=$1
    if [[ ! -d $worktree_path ]]; then
        echo "cdw: path does not exist: $worktree_path"
        return 1
    fi
    cd "$worktree_path"
}

_cdw_confirm() {
    local prompt=$1 char
    printf '%s' "$prompt"
    read -k 1 char
    print ''
    if [[ $char == $'\e' ]]; then
        return 2
    elif [[ $char == [yY] ]]; then
        return 0
    else
        return 1
    fi
}

typeset -g _cdw_vared_escaped=0

_cdw_vared_escape_widget() {
    _cdw_vared_escaped=1
    zle send-break
}
zle -N _cdw_vared_escape_widget

_cdw_delete() {
    local worktree_path=$1 main_path=$2 branch_name=$3
    if [[ $worktree_path == "$main_path" ]]; then
        echo "cdw: cannot delete the main worktree"
        return 1
    fi
    _cdw_confirm "Remove $worktree_path? [y/N] "
    local confirm_rc=$?
    (( confirm_rc == 2 )) && return 2
    (( confirm_rc != 0 )) && return 0
    if ! PATH="$_CDW_PATH" git worktree remove "$worktree_path"; then
        echo "cdw: worktree has uncommitted changes; remove manually with: git worktree remove --force $worktree_path"
        return 1
    fi
    [[ -z $branch_name ]] && return 0
    local setting
    setting=$(_cdw_read_rc_key "$main_path" "delete_branch") || setting=ask
    [[ $setting != delete && $setting != skip && $setting != ask ]] && setting=ask
    [[ $setting == skip ]] && return 0
    if [[ $setting == ask ]]; then
        _cdw_confirm "Also delete branch '$branch_name'? [y/N] "
        local confirm_rc=$?
        (( confirm_rc == 2 )) && return 2
        (( confirm_rc != 0 )) && return 0
    fi
    if PATH="$_CDW_PATH" git branch -d "$branch_name" 2>/dev/null; then
        echo "cdw: deleted branch '$branch_name'"
    else
        echo "cdw: could not delete branch '$branch_name'"
        echo "cdw: to force-delete: git branch -D $branch_name"
    fi
}

_cdw_create() {
    local main_path=$1
    local branch_name hook_cmd
    branch_name=$(_cdw_read_rc_key "$main_path" "branch_prefix")
    typeset -g _cdw_vared_escaped=0
    local prior_esc
    prior_esc=$(bindkey '\e' 2>/dev/null | awk '{print $2}')
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
    if ! cd "$derived_path"; then
        echo "cdw: could not cd into $derived_path"
        return 1
    fi
    hook_cmd=$(_cdw_read_rc_key "$main_path" "post_create")
    _cdw_run_hook "$hook_cmd" "$branch_name" "$derived_path"
}

typeset -gA _cdw_handlers
_cdw_handlers=(
    bspace _cdw_delete
)

cdw() {
    _cdw_check_fzf || return 1
    _cdw_check_git || return 1

    local main_path
    main_path=$(PATH="$_CDW_PATH" git worktree list 2>/dev/null | head -1 | awk '{print $1}')
    if [[ -z $main_path ]]; then
        echo "cdw: could not determine main worktree path"
        return 1
    fi

    local output key selected fzf_exit
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

    if [[ $selected == '[+ new worktree]' ]]; then
        [[ $key == 'bspace' ]] && return 0
        _cdw_create "$main_path"
        return
    fi

    local worktree_path
    worktree_path=$(awk '{print $1}' <<< "$selected")

    local branch_raw branch_name
    branch_raw=$(awk '{print $3}' <<< "$selected")
    if [[ $branch_raw == \(* || -z $branch_raw ]]; then
        branch_name=''
    else
        branch_name=${branch_raw//[\[\]]/}
    fi

    if [[ -z $key ]]; then
        _cdw_cd "$worktree_path"
    elif (( ${+_cdw_handlers[$key]} )); then
        ${_cdw_handlers[$key]} "$worktree_path" "$main_path" "$branch_name"
    fi
}
