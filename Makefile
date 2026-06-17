.PHONY: install uninstall lint

install:
	@./install.sh install

uninstall:
	@./install.sh uninstall

lint:
	@shellcheck -s bash cdw.zsh
