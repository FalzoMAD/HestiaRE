# ======================================================== #
# HestiaRE Makefile — orchestrator
# Install logic lives in make/*.mk
#
# Usage:
#   make install OS=debian-bookworm [PROFILE=standard]
#   make install OS=debian-bookworm \
#        H_HOSTNAME=host.example.com H_ADMIN=admin \
#        H_EMAIL=admin@host H_PASS=secret
#   make add-tools [TOOLS_SET=hestia|sysadmin|full]
#   make update | check-updates | status
# ======================================================== #

.ONESHELL:
SHELL        := /bin/bash
.SHELLFLAGS  := -euo pipefail -c
MAKEFLAGS    += --no-print-directory

HESTIA             := /usr/local/hestia
CONF_DIR           := /etc/hestia
INSTALL_CONF       := $(CONF_DIR)/install.conf
SOURCE_CONF        := $(CONF_DIR)/source.conf
LOG                := /var/log/hestia/install.log
VERSION            := $(shell cat $(HESTIA)/VERSION 2>/dev/null || cat VERSION 2>/dev/null || echo "dev")
ARCH               := $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

OS                 ?= unknown
PROFILE            ?= standard
H_HOSTNAME         ?=
H_ADMIN            ?=
H_EMAIL            ?=
H_PASS             ?=

MARIADB_VER        := 11.8
PHP_VER            := 8.3
PMA_VER            := 5.2.3
MULTIPHP_VER       := 5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3 8.4 8.5
TOOLS_SET          ?= hestia

HESTIA_INSTALL_DIR := $(HESTIA)/install/deb
HESTIA_COMMON_DIR  := $(HESTIA)/install/common

-include $(SOURCE_CONF)

HESTIARE_SOURCE    ?= github
HESTIARE_REPO_URL  ?= https://github.com/FalzoMAD/HestiaRE
HESTIARE_TOKEN     ?=
HESTIARE_CHANNEL   ?= stable

GITHUB_REPO        := FalzoMAD/HestiaRE
GITHUB_API         := https://api.github.com/repos/$(GITHUB_REPO)
GITHUB_RAW         := https://github.com/$(GITHUB_REPO)/releases/download

# OS-specific vars (OS_ID, CODENAME, RELEASE, EXIM_USR, BASE_PKGS_EXTRA)
-include make/$(OS).mk

include make/base.mk
include make/panel.mk
include make/web.mk
include make/db.mk
include make/mail.mk
include make/security.mk
include make/tools.mk
include make/configure.mk

.PHONY: install _profile-standard _profile-minimal \
        update _do-update check-updates status backup uninstall

# -------------------------------------------------------- #
# install — main entry point
# -------------------------------------------------------- #

install:
	@echo "========================================================================"
	echo " HestiaRE $(VERSION)"
	echo " OS:      $(OS)"
	echo " Profile: $(PROFILE)"
	echo "========================================================================"
	echo ""
	$(MAKE) _check-root
	$(MAKE) _collect-params H_HOSTNAME="$(H_HOSTNAME)" H_ADMIN="$(H_ADMIN)" \
	    H_EMAIL="$(H_EMAIL)" H_PASS="$(H_PASS)"
	$(MAKE) _install-base
	$(MAKE) _install-panel
	$(MAKE) _install-web
	$(MAKE) _install-db
	$(MAKE) _profile-$(PROFILE)
	$(MAKE) _install-security
	$(MAKE) _configure-hestia
	$(MAKE) add-tools TOOLS_SET="$(TOOLS_SET)"
	$(MAKE) _finalize

_profile-standard:
	$(MAKE) _install-mail

_profile-minimal:
	@echo "[ * ] Minimal profile — skipping mail stack"

# -------------------------------------------------------- #
# update / check-updates
# -------------------------------------------------------- #

update: check-updates
	@$(MAKE) _do-update

_do-update:
	@if [ "$(HESTIARE_SOURCE)" = "gitea" ]; then \
	    AUTH=""; \
	    [ -n "$(HESTIARE_TOKEN)" ] && AUTH="-H \"Authorization: token $(HESTIARE_TOKEN)\""; \
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
	echo "Updating to $$LATEST..."; \
	curl -fsSL "$$URL" -o /tmp/hestiare-update.tar.gz; \
	tar -xzf /tmp/hestiare-update.tar.gz -C /tmp; \
	rm /tmp/hestiare-update.tar.gz; \
	cp -r /tmp/hestiare-$$LATEST/. $(HESTIA)/; \
	rm -rf /tmp/hestiare-$$LATEST; \
	echo "Update complete."

check-updates:
	@echo "Checking for updates..."
	if [ "$(HESTIARE_SOURCE)" = "gitea" ]; then \
	    AUTH=""; \
	    [ -n "$(HESTIARE_TOKEN)" ] && AUTH="-H \"Authorization: token $(HESTIARE_TOKEN)\""; \
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
# status / backup / uninstall
# -------------------------------------------------------- #

status:
	@echo "HestiaRE $(VERSION)"
	echo "Source:   $(HESTIARE_SOURCE)"
	echo "Channel:  $(HESTIARE_CHANNEL)"
	echo "OS:       $(OS)"
	echo "Profile:  $(PROFILE)"
	echo ""
	echo "Completed install phases:"
	for s in $(CONF_DIR)/.done.*; do \
	    [ -f "$$s" ] && echo "  + $${s##*/.done.}" || true; \
	done

backup:
	@echo "HestiaRE — backup placeholder"

uninstall:
	@echo "========================================================================"
	echo " HestiaRE Uninstall"
	echo "========================================================================"
	echo ""
	read -p "This will remove HestiaRE. Are you sure? [y/N] " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
	    echo "Aborted."; \
	    exit 1; \
	fi
	echo "Uninstall placeholder — nothing removed yet."
	echo ""
	echo "Done."
