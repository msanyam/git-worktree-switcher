# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

`cdw` is a single zsh function (`cdw.zsh`) that provides an interactive fzf-powered interface for switching between, creating, and deleting git worktrees.

## Running Tests

Do not write or execute tests in this repository.

## Architecture

`cdw.zsh` is structured in four layers (top to bottom):

1. **PATH constant** — `_CDW_PATH` prefixes all `git`/`fzf` invocations to ensure Homebrew binaries are found on Apple Silicon
2. **Guards** — `_cdw_check_fzf`, `_cdw_check_git` — called once at entry, return 1 with a `cdw:` error message if their precondition fails
3. **Handlers** — one function per action, all accepting `($worktree_path $main_path)` except `_cdw_create` which takes `($main_path)` only
4. **Dispatch table + entry point** — `_cdw_handlers` associative array maps fzf `--expect` key names to handler functions; `cdw()` is the sole public entry point

### Key design decisions

- `enter` is **not** in the dispatch table — fzf's default exit key emitting an empty key line is how Enter presses are detected
- The sentinel item `[+ new worktree]` is detected by content comparison before key dispatch, not via `--expect`
- `_cdw_create` derives the worktree path as `${main_path}/.worktrees/${branch_name//\//-}` — slashes in branch names become dashes
- Adding a new key-bound action: write a `_cdw_<action>` handler, add one entry to `_cdw_handlers`, update the header string

### Submodule subsystem

`cdw init-submodules` and `cdw delete-submodules` are non-interactive subcommands dispatched from `cdw()` before the fzf loop. Each has a three-layer stack:

| Layer | init | delete |
|---|---|---|
| Entry (CLI dispatch) | `_cdw_cmd_init_submodules` | `_cdw_cmd_delete_submodules([--force])` |
| Lock + summary | `_cdw_init_submodule_worktrees` | `_cdw_delete_submodule_worktrees` |
| Recursive worker | `_cdw_add_submodule_worktrees` | `_cdw_remove_submodule_worktrees` |

Both stacks use `_cdw_with_submodule_lock` (flock on `$common_dir/cdw-submodules.lock`), the `_cdw_sm_ok` / `_cdw_sm_failed` globals, and a depth cap of 2 for nested submodules. Delete is depth-first (children removed before parents). `_cdw_rollback_submodule` is error-recovery only — not called by delete. Adding a new subcommand: add a branch in `cdw()` and a matching `case` entry in the script-mode block at the bottom of `cdw.zsh`.

## Commit Format

`[cdw] :<gitmoji>: <short description>` — no attribution line. See existing commits for examples.
