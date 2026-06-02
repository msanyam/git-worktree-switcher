#!/usr/bin/env zsh
# Installs cdw by symlinking cdw.zsh into ~/.local/bin/ and sourcing it from ~/.zshrc.
# Usage: ./install.sh [install|uninstall]

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
SYMLINK="$BIN_DIR/cdw"
ZSHRC="$HOME/.zshrc"
SCRIPT_DIR="${0:A:h}"
TARGET="$SCRIPT_DIR/cdw.zsh"

_cdw_confirm() {
    printf '%s' "$1"
    read -k 1 _reply < /dev/tty
    print ''
    [[ $_reply == [yY] ]]
}

_cdw_install() {
    mkdir -p "$BIN_DIR"

    if [[ -L "$SYMLINK" && "$(readlink "$SYMLINK")" == "$TARGET" ]]; then
        echo "cdw: symlink already installed"
    elif [[ -e "$SYMLINK" || -L "$SYMLINK" ]]; then
        echo "cdw: $SYMLINK already exists and points elsewhere — skipping (remove it manually if you want to reinstall)"
    else
        ln -s "$TARGET" "$SYMLINK"
        echo "cdw: installed $SYMLINK -> $TARGET"
    fi

    if [[ ! -e "$HOME/.cdwrc" ]]; then
        cp "$SCRIPT_DIR/.cdwrc" "$HOME/.cdwrc"
        echo "cdw: installed ~/.cdwrc"
    else
        echo "cdw: ~/.cdwrc already exists, skipping"
    fi

    if [[ -f "$ZSHRC" ]] && grep -qF '# cdw:begin' "$ZSHRC"; then
        echo "cdw: ~/.zshrc already configured"
        return 0
    fi

    # Remove stale source lines from a prior Makefile/install.sh install
    if [[ -f "$ZSHRC" ]] && grep -qE 'cdw\.zsh' "$ZSHRC"; then
        sed -i.cdwbak '/# cdw - git worktree switcher/d; /cdw\.zsh/d' "$ZSHRC"
        echo "cdw: removed stale cdw source lines from ~/.zshrc (backup: ~/.zshrc.cdwbak)"
    fi

    printf '\n\n# cdw:begin\nsource ~/.local/bin/cdw\n# cdw:end\n' >> "$ZSHRC"
    echo "cdw: added to ~/.zshrc — run: source ~/.zshrc"
}

_cdw_uninstall() {
    if [[ -L "$SYMLINK" ]]; then
        if _cdw_confirm "Remove $SYMLINK? [y/N] "; then
            rm "$SYMLINK"
            echo "cdw: removed $SYMLINK"
        else
            echo "cdw: kept $SYMLINK"
        fi
    fi

    if [[ -L "$HOME/.cdwrc" || -f "$HOME/.cdwrc" ]]; then
        if _cdw_confirm "Remove ~/.cdwrc? [y/N] "; then
            rm "$HOME/.cdwrc"
            echo "cdw: removed ~/.cdwrc"
        else
            echo "cdw: kept ~/.cdwrc"
        fi
    fi

    if [[ -f "$ZSHRC" ]] && grep -qF '# cdw:begin' "$ZSHRC"; then
        sed -i.cdwbak '/# cdw:begin/,/# cdw:end/d' "$ZSHRC"
        echo "cdw: removed cdw block from ~/.zshrc (backup: ~/.zshrc.cdwbak)"
    elif [[ -f "$ZSHRC" ]] && grep -qE 'cdw\.zsh' "$ZSHRC"; then
        sed -i.cdwbak '/# cdw - git worktree switcher/d; /cdw\.zsh/d' "$ZSHRC"
        echo "cdw: removed stale cdw source lines from ~/.zshrc (backup: ~/.zshrc.cdwbak)"
    fi
}

case "${1:-install}" in
    install)   _cdw_install   ;;
    uninstall) _cdw_uninstall ;;
    *)
        echo "usage: $0 [install|uninstall]" >&2
        exit 1
        ;;
esac
