# git-worktree-switcher

`cdw` is a tiny zsh function that lets you switch between, create, and delete git worktrees interactively using [fzf](https://github.com/junegunn/fzf).

## Demo

https://github.com/user-attachments/assets/36807d45-ed0e-4c13-b9d2-ee9779192a6a

## Features

- **Switch worktrees** — fuzzy-search and `cd` into any worktree instantly
- **Create worktrees** — select `[+ new worktree]`, type a branch name, and the worktree is created and checked out under `<repo>/.worktrees/<branch>`
- **Delete worktrees** — press Backspace on any worktree to remove it (with confirmation prompt)
- **Delete branch on worktree removal** — optionally delete the linked branch when removing a worktree (configurable via `.cdwrc`)
- **Protected main worktree** — the main worktree can never be deleted
- **Uncommitted-change safety** — refuses to delete a worktree with uncommitted changes and prints the manual override command
- **Escape to reopen** — pressing Escape in the fzf picker reopens it instead of exiting `cdw`
- **Post-create hook** — run a shell command automatically after creating a new worktree (e.g. install dependencies)
- **`.cdwrc` config file** — configure branch prefix, post-create hook, and branch deletion behavior
- **Homebrew fzf support** — `/opt/homebrew/bin` is always in PATH so fzf works on Apple Silicon without extra shell config

## Requirements

- zsh
- git
- [fzf](https://github.com/junegunn/fzf)

## Installation

### Makefile (recommended)

```zsh
make install
```

This symlinks `.cdwrc` to `~/.cdwrc` and adds a `source` line for `cdw.zsh` to your `~/.zshrc`. Restart your shell or run `source ~/.zshrc` afterwards.

To uninstall:

```zsh
make uninstall
```

This removes the `~/.cdwrc` symlink (with confirmation) and prints the lines to manually remove from `~/.zshrc`.

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
| **Esc** | Close and reopen the picker (from branch name prompt); cancel from fzf |
| **Ctrl-C** | Cancel |

## Configuration

`cdw` reads `~/.cdwrc` for configuration. Each line is a `key=value` pair.

| Key | Values | Default | Description |
|-----|--------|---------|-------------|
| `branch_prefix` | any string | _(empty)_ | Pre-fills the branch name input when creating a worktree |
| `post_create` | shell command | _(empty)_ | Runs after a new worktree is created; receives `CDW_BRANCH` and `CDW_WORKTREE_PATH` as env vars |
| `delete_branch` | `ask`, `always`, `skip` | `ask` | Controls branch deletion when removing a worktree |

### Branch prefix

Set `branch_prefix` to pre-fill the branch name input when creating a worktree:

```ini
# ~/.cdwrc
branch_prefix=feat/
```

This is equivalent to the old `GIT_BRANCH_PREFIX` env var (still supported via the env var if you prefer).

### Post-create hook

Run a command automatically after a new worktree is created:

```ini
# ~/.cdwrc
post_create=npm install
```

The hook receives two environment variables:

- `CDW_BRANCH` — the branch name
- `CDW_WORKTREE_PATH` — the absolute path of the new worktree

If the hook exits non-zero, `cdw` prints a warning but does not abort.

### Branch deletion on worktree removal

Control what happens to the branch when you delete a worktree:

```ini
# ~/.cdwrc
delete_branch=ask     # prompt each time (default)
delete_branch=always  # always delete the branch
delete_branch=skip    # never delete the branch
```

### Worktree location

New worktrees are created at `<main-repo-path>/.worktrees/<branch-name>` (slashes in branch names are converted to dashes).
