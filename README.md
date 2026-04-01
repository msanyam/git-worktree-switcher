# git-worktree-switcher

`cdw` is a tiny zsh function that lets you switch between, create, and delete git worktrees interactively using [fzf](https://github.com/junegunn/fzf).

## Demo

![demo](demo.gif)

## Features

- **Switch worktrees** — fuzzy-search and `cd` into any worktree instantly
- **Create worktrees** — select `[+ new worktree]`, type a branch name, and the worktree is created and checked out under `<repo>/.worktrees/<branch>`
- **Delete worktrees** — press Backspace on any worktree to remove it (with confirmation prompt)
- **Protected main worktree** — the main worktree can never be deleted
- **Uncommitted-change safety** — refuses to delete a worktree with uncommitted changes and prints the manual override command
- **Homebrew fzf support** — `/opt/homebrew/bin` is always in PATH so fzf works on Apple Silicon without extra shell config
- **`GIT_BRANCH_PREFIX` support** — set this env var to pre-fill the branch name prompt when creating a worktree

## Requirements

- zsh
- git
- [fzf](https://github.com/junegunn/fzf)

## Installation

### Manual

Copy `cdw.zsh` somewhere and source it in your `.zshrc`:

```zsh
source ~/.zsh_functions/cdw.zsh
```

### Oh My Zsh

Place `cdw.zsh` in `~/.oh-my-zsh/custom/` — it will be sourced automatically.

## Usage

Run `cdw` from any directory inside a git repository:

```zsh
cdw
```

| Key | Action |
|-----|--------|
| Type / arrow keys | Filter and navigate worktrees |
| **Enter** | `cd` into the selected worktree |
| **Enter** on `[+ new worktree]` | Prompt for a branch name, create the worktree, and `cd` into it |
| **Backspace** | Delete the selected worktree (confirmation required) |
| **Esc / Ctrl-C** | Cancel |

### Branch prefix

Set `GIT_BRANCH_PREFIX` to pre-fill the branch name input when creating a worktree:

```zsh
export GIT_BRANCH_PREFIX="feat/"
cdw  # branch name prompt starts with "feat/"
```

### Worktree location

New worktrees are created at `<main-repo-path>/.worktrees/<branch-name>` (slashes in branch names are converted to dashes).
