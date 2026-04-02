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

## Commit Format

`[cdw] :<gitmoji>: <short description>` — no attribution line. See existing commits for examples.
