PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
SCRIPT := $(CURDIR)/uua

.PHONY: check test install link uninstall

# Syntax-check the script without running it.
check:
	zsh -n $(SCRIPT)
	$(SCRIPT) --version

# Unit and command-line tests against stub commands; no network or sudo.
test: check
	zsh tests/test.zsh

# Copy into $(BINDIR), independent of this checkout. The rm first keeps
# install from writing through a symlink left by `make link`.
install:
	mkdir -p $(BINDIR)
	rm -f $(BINDIR)/uua
	install -m 755 $(SCRIPT) $(BINDIR)/uua

# Symlink instead, so edits here take effect immediately (development).
link:
	mkdir -p $(BINDIR)
	ln -sfn $(SCRIPT) $(BINDIR)/uua

uninstall:
	rm -f $(BINDIR)/uua
