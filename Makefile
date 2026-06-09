# ======================================================== #
#
# HestiaRE Makefile
#
# ======================================================== #

SOURCE_CONF  := /etc/hestia-re/source.conf
INSTALL_DIR  := /usr/local/hestia-re
CONF_DIR     := /etc/hestia-re

OS           ?= unknown
PROFILE      ?= standard
VERSION      := $(shell cat VERSION 2>/dev/null || echo "dev")

# Load source config if exists
-include $(SOURCE_CONF)

HESTIARE_SOURCE      ?= github
HESTIARE_REPO_URL    ?= https://github.com/FalzoMAD/HestiaRE
HESTIARE_TOKEN       ?=
HESTIARE_CHANNEL     ?= stable

# GitHub defaults
GITHUB_REPO          := FalzoMAD/HestiaRE
GITHUB_API           := https://api.github.com/repos/$(GITHUB_REPO)
GITHUB_RAW           := https://github.com/$(GITHUB_REPO)/releases/download

# OS abstraction
OS_CONF := conf/os/$(OS).mk
-include $(OS_CONF)

.PHONY: install update uninstall status backup check-updates

# -------------------------------------------------------- #
# install
# -------------------------------------------------------- #
install:
	@echo "================================================"
	@echo " HestiaRE $(VERSION)"
	@echo " OS:      $(OS)"
	@echo " Profile: $(PROFILE)"
	@echo "================================================"
	@echo ""
	@echo " Installation placeholder – nothing installed yet."
	@echo ""
	@echo " Done."

# -------------------------------------------------------- #
# update
# -------------------------------------------------------- #
update: check-updates
	@echo "Downloading update..."
	@$(MAKE) _do-update

_do-update:
	@if [ "$(HESTIARE_SOURCE)" = "gitea" ]; then \
		AUTH=""; \
		if [ -n "$(HESTIARE_TOKEN)" ]; then AUTH="-H \"Authorization: token $(HESTIARE_TOKEN)\""; fi; \
		LATEST=$$(curl -fsSL $$AUTH "$(HESTIARE_REPO_URL)/releases/latest" \
			| grep '"tag_name"' | cut -d'"' -f4); \
		URL="$(HESTIARE_REPO_URL)/releases/download/$$LATEST/hestiare-$$LATEST.tar.gz"; \
	else \
		if [ "$(HESTIARE_CHANNEL)" = "prerelease" ]; then \
			LATEST=$$(curl -fsSL "$(GITHUB_API)/releases" \
				| grep '"tag_name"' | head -n1 | cut -d'"' -f4); \
		else \
			LATEST=$$(curl -fsSL "$(GITHUB_API)/releases/latest" \
				| grep '"tag_name"' | cut -d'"' -f4); \
		fi; \
		URL="$(GITHUB_RAW)/$$LATEST/hestiare-$$LATEST.tar.gz"; \
	fi; \
	echo "Version: $$LATEST"; \
	curl -fsSL "$$URL" -o /tmp/hestiare-update.tar.gz; \
	tar -xzf /tmp/hestiare-update.tar.gz -C /tmp; \
	rm /tmp/hestiare-update.tar.gz; \
	cp -r /tmp/hestiare-$$LATEST/. $(INSTALL_DIR)/; \
	rm -rf /tmp/hestiare-$$LATEST; \
	cd $(INSTALL_DIR) && $(MAKE) install OS="$(OS)" PROFILE="$(PROFILE)"; \
	echo "Update complete."

# -------------------------------------------------------- #
# check-updates
# -------------------------------------------------------- #
check-updates:
	@echo "Checking for updates..."
	@if [ "$(HESTIARE_SOURCE)" = "gitea" ]; then \
		AUTH=""; \
		if [ -n "$(HESTIARE_TOKEN)" ]; then AUTH="-H \"Authorization: token $(HESTIARE_TOKEN)\""; fi; \
		LATEST=$$(curl -fsSL $$AUTH "$(HESTIARE_REPO_URL)/releases/latest" \
			| grep '"tag_name"' | cut -d'"' -f4); \
	else \
		LATEST=$$(curl -fsSL "$(GITHUB_API)/releases/latest" \
			| grep '"tag_name"' | cut -d'"' -f4); \
	fi; \
	echo "Installed: $(VERSION)"; \
	echo "Available: $$LATEST"; \
	if [ "$$LATEST" = "v$(VERSION)" ] || [ "$$LATEST" = "$(VERSION)" ]; then \
		echo "Already up to date."; \
	else \
		echo "Update available: $$LATEST"; \
	fi

# -------------------------------------------------------- #
# status
# -------------------------------------------------------- #
status:
	@echo "HestiaRE $(VERSION)"
	@echo "Source:   $(HESTIARE_SOURCE)"
	@echo "Channel:  $(HESTIARE_CHANNEL)"
	@echo "OS:       $(OS)"
	@echo "Profile:  $(PROFILE)"

# -------------------------------------------------------- #
# backup
# -------------------------------------------------------- #
backup:
	@echo "HestiaRE – backup placeholder"

# -------------------------------------------------------- #
# uninstall
# -------------------------------------------------------- #
uninstall:
	@echo "================================================"
	@echo " HestiaRE Uninstall"
	@echo "================================================"
	@echo ""
	@read -p "This will remove HestiaRE. Are you sure? [y/N] " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "Aborted."; \
		exit 1; \
	fi
	@echo "Uninstall placeholder – nothing removed yet."
	@echo ""
	@echo "Done."
