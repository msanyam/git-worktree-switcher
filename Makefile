REPO_DIR  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CDWRC     := $(REPO_DIR).cdwrc
CDW_ZSH   := $(REPO_DIR)cdw.zsh
HOME_RC   := $(HOME)/.cdwrc
ZSHRC     := $(HOME)/.zshrc
SOURCE_LINE := source "$(CDW_ZSH)"

.PHONY: install uninstall

install:
	@# --- .cdwrc symlink ---
	@if [ -L "$(HOME_RC)" ] && [ "$$(readlink "$(HOME_RC)")" = "$(CDWRC)" ]; then \
		echo "cdw: ~/.cdwrc already installed"; \
	elif [ -L "$(HOME_RC)" ] || [ -e "$(HOME_RC)" ]; then \
		echo "cdw: ~/.cdwrc already exists, skipping"; \
	else \
		ln -s "$(CDWRC)" "$(HOME_RC)"; \
		echo "cdw: installed ~/.cdwrc -> $(CDWRC)"; \
	fi
	@# --- zshrc source line ---
	@if grep -qF '$(SOURCE_LINE)' "$(ZSHRC)" 2>/dev/null; then \
		echo "cdw: ~/.zshrc already sources cdw.zsh"; \
	else \
		echo '' >> "$(ZSHRC)"; \
		echo '# cdw - git worktree switcher' >> "$(ZSHRC)"; \
		echo '$(SOURCE_LINE)' >> "$(ZSHRC)"; \
		echo "cdw: added source line to ~/.zshrc"; \
		echo "cdw: restart your shell or run: source ~/.zshrc"; \
	fi

uninstall:
	@# --- .cdwrc symlink ---
	@if [ -L "$(HOME_RC)" ] && [ "$$(readlink "$(HOME_RC)")" = "$(CDWRC)" ]; then \
		printf 'Remove ~/.cdwrc? [y/N] '; \
		read confirm < /dev/tty; \
		case "$$confirm" in \
			[yY]) rm "$(HOME_RC)"; echo "cdw: removed ~/.cdwrc" ;; \
			*)    echo "cdw: kept ~/.cdwrc" ;; \
		esac; \
	elif [ -L "$(HOME_RC)" ] || [ -e "$(HOME_RC)" ]; then \
		printf 'cdw: ~/.cdwrc exists but is not managed by this repo. Delete it? [y/N] '; \
		read confirm < /dev/tty; \
		case "$$confirm" in \
			[yY]) rm "$(HOME_RC)"; echo "cdw: removed ~/.cdwrc" ;; \
			*)    echo "cdw: kept ~/.cdwrc" ;; \
		esac; \
	fi
	@# --- zshrc source line ---
	@if grep -qF 'cdw.zsh' "$(ZSHRC)" 2>/dev/null; then \
		echo "cdw: remove these lines from ~/.zshrc manually:"; \
		grep -nF 'cdw.zsh' "$(ZSHRC)"; \
	fi
