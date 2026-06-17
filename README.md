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
- **Uncommitted-change safety** — prompts for force-remove confirmation when a worktree has uncommitted or untracked changes
- **Escape to reopen** — pressing Escape in the fzf picker reopens it instead of exiting `cdw`
- **Post-create hook** — run a shell command automatically after creating a new worktree (e.g. install dependencies)
- **Post-selection hook** — run a shell command automatically after switching to a worktree (e.g. activate an env)
- **Submodule worktree init** — automatically creates linked worktrees for all submodules when creating a new worktree; concurrent-safe (flock), validated, with per-submodule rollback and stale-registration pruning on delete
- **`.cdwrc` config file** — configure branch prefix, hooks, and branch deletion behavior
- **Homebrew fzf support** — `/opt/homebrew/bin` is always in PATH so fzf works on Apple Silicon without extra shell config

## Requirements

- zsh
- git
- [fzf](https://github.com/junegunn/fzf)

## Installation

### install.sh (recommended)

```zsh
./install.sh
```

This creates a symlink `~/.local/bin/cdw` → `cdw.zsh` and adds a `source` line to `~/.zshrc`. Restart your shell or run `source ~/.zshrc` afterwards. Because the symlink points into the repo, `git pull` automatically picks up updates — no reinstall needed.

The repo must stay in its installed location. If you move it, run `./install.sh uninstall && ./install.sh` to update the symlink.

To uninstall (removes the symlink and the `~/.zshrc` entry automatically):

```zsh
./install.sh uninstall
```

`make install` / `make uninstall` are also available as aliases.

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
| `post_selection` | shell command | _(empty)_ | Runs after switching to a worktree; receives `CDW_WORKTREE_PATH` as an env var |
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

### Post-selection hook

Run a command automatically after switching into a worktree:

```ini
# ~/.cdwrc
post_selection=. .venv/bin/activate
```

The hook receives one environment variable:

- `CDW_WORKTREE_PATH` — the absolute path of the selected worktree

If the hook exits non-zero, `cdw` prints a warning but does not abort.

### Branch deletion on worktree removal

When deleting a worktree that has uncommitted or untracked changes, `cdw` prompts for confirmation before running `git worktree remove --force`.

Control what happens to the branch when you delete a worktree:

```ini
# ~/.cdwrc
delete_branch=ask     # prompt each time (default)
delete_branch=always  # always delete the branch
delete_branch=skip    # never delete the branch
```

### Worktree location

New worktrees are created at `<main-repo-path>/.worktrees/<branch-name>` (slashes in branch names are converted to dashes).

## Submodule support

When you create a worktree in a repo that has submodules, `cdw` automatically initializes each submodule as a *linked worktree* of the main checkout's submodule repo — sharing the object store and refs instead of re-cloning.

- **Concurrent-safe** — a `zsystem flock`-based lock (no external binary) serialises init across all worktrees and parallel `cdw` runs of the same superproject, preventing gitdir-collision corruption.
- **Validated** — checks the submodule store is a healthy repo, the submodule is initialized in the main checkout, and the pinned commit exists locally; fails loudly instead of silently producing a broken state.
- **`extensions.worktreeConfig` enabled automatically** — prevents `core.worktree` from being written to the shared config (which would clobber the existing checkout's value). Any pre-existing shared `core.worktree` is migrated to the main worktree's `config.worktree` transparently.
- **No network** — strictly local; never fetches from a remote. Run `git submodule update --init` in the main checkout first.
- **Per-submodule rollback** — if a submodule fails, it's rolled back cleanly; other submodules and the parent worktree are unaffected.
- **Progress summary** — prints `cdw: initialized X of Y submodules` after each create.
- **Clean delete** — stale submodule worktree registrations are pruned automatically when the parent worktree is removed.
