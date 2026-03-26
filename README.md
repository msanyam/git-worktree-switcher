# git-worktree-switcher

`cdw` is a tiny zsh function that lets you switch between (and delete) git worktrees interactively using [fzf](https://github.com/junegunn/fzf).

## Demo

```
  /Users/you/projects/myrepo        abc1234 [main]
  /Users/you/projects/myrepo-feat   def5678 [feat/new-feature]
  /Users/you/projects/myrepo-fix    ghi9012 [fix/some-bug]

  Enter: cd  ⌫: delete
```

- **Enter** — `cd` into the selected worktree
- **Backspace** — delete the selected worktree (with confirmation; main worktree is protected)

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

### Homebrew fzf (Apple Silicon)

The function explicitly includes `/opt/homebrew/bin` in `PATH` when calling git, so it works correctly even if your shell profile hasn't added Homebrew's bin directory yet.

## Usage

Run `cdw` from any directory inside a git repository:

```zsh
cdw
```

Use arrow keys or type to filter worktrees. Press **Enter** to cd into one, or **Backspace** to remove one.
