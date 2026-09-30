PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
SCRIPT := $(CURDIR)/uua

SPEED ?= 1

.PHONY: check test demo install link uninstall

# Syntax-check the script without running it.
check:
	zsh -n $(SCRIPT)
	$(SCRIPT) --version

# Unit and command-line tests against stub commands; no network or sudo.
test: check
	zsh tests/test.zsh

# A full run with the live board, against a fake system built by
# tests/fakesys.zsh in a temporary directory: nothing real is updated.
# SPEED=0.5 halves the pauses.
demo:
	@dir="$$(mktemp -d)" && zsh tests/fakesys.zsh "$$dir" && \
	  env -i $$(zsh tests/fakesys.zsh "$$dir" env) TERM="$$TERM" LANG="$${LANG:-C.UTF-8}" \
	    FAKE_SPEED=$(SPEED) zsh $(SCRIPT) --prune; \
	  rm -rf "$$dir"

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
