cdw() {
    if ! command -v fzf &>/dev/null; then
        echo "cdw: fzf not found"
        return 1
    fi

    if ! PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH" git rev-parse --is-inside-work-tree &>/dev/null; then
        echo "cdw: not a git repository"
        return 1
    fi

    local main_path output key selected worktree_path
    main_path=$(PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH" git worktree list | head -1 | awk '{print $1}')

    output=$(PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH" git worktree list | fzf \
        --expect=bspace \
        --height=40% \
        --reverse \
        --no-info \
        --header='Enter: cd  ⌫: delete')

    key=$(head -1 <<< "$output")
    selected=$(tail -1 <<< "$output")

    [[ -z $selected ]] && return 0

    worktree_path=$(awk '{print $1}' <<< "$selected")

    if [[ $key == "bspace" ]]; then
        if [[ $worktree_path == "$main_path" ]]; then
            echo "cdw: cannot delete the main worktree"
            return 1
        fi
        local confirm
        read -r "confirm?Remove $worktree_path? [y/N] "
        if [[ $confirm =~ ^[Yy]$ ]]; then
            git worktree remove "$worktree_path" || echo "cdw: worktree has uncommitted changes; remove manually with: git worktree remove --force $worktree_path"
        fi
    else
        if [[ ! -d $worktree_path ]]; then
            echo "cdw: path does not exist: $worktree_path"
            return 1
        fi
        cd "$worktree_path"
    fi
}
