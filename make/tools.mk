# -------------------------------------------------------- #
# tools.mk — sysadmin and hestia tooling
#            public target: always re-runnable, no sentinel
# -------------------------------------------------------- #

.PHONY: add-tools

TOOLS_SET ?= hestia

TOOLS_HESTIA  := composer wp-cli
TOOLS_SYSADM  := htop ncdu tmux mtr-tiny nmap iotop traceroute
TOOLS_FULL    := rclone restic

add-tools:
	echo "[ * ] Installing tools (TOOLS_SET=$(TOOLS_SET))..."
	case "$(TOOLS_SET)" in \
	    hestia) \
	        echo "  Set: composer, wp-cli"; \
	        ;; \
	    sysadmin) \
	        echo "  Set: composer, wp-cli + sysadmin utilities"; \
	        DEBIAN_FRONTEND=noninteractive apt-get -y install $(TOOLS_SYSADM) >> $(LOG); \
	        ;; \
	    full) \
	        echo "  Set: composer, wp-cli + sysadmin + rclone/restic"; \
	        DEBIAN_FRONTEND=noninteractive apt-get -y install $(TOOLS_SYSADM) >> $(LOG); \
	        DEBIAN_FRONTEND=noninteractive apt-get -y install $(TOOLS_FULL) >> $(LOG); \
	        ;; \
	    *) \
	        echo "ERROR: Unknown TOOLS_SET '$(TOOLS_SET)'. Valid: hestia|sysadmin|full" >&2; \
	        exit 1; \
	        ;; \
	esac
	echo "[ * ] Installing composer (system-wide)..."
	if ! command -v composer > /dev/null 2>&1; then \
	    EXPECTED_CHECKSUM="$$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"; \
	    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"; \
	    ACTUAL_CHECKSUM="$$(php -r "echo hash_file('sha384', 'composer-setup.php');")"; \
	    if [ "$$EXPECTED_CHECKSUM" != "$$ACTUAL_CHECKSUM" ]; then \
	        rm -f composer-setup.php; \
	        echo "ERROR: Composer installer checksum mismatch" >&2; \
	        exit 1; \
	    fi; \
	    php composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer; \
	    rm -f composer-setup.php; \
	    echo "  composer installed"; \
	else \
	    echo "  composer already present — upgrading"; \
	    composer self-update --quiet 2>/dev/null || true; \
	fi
	echo "[ * ] Installing wp-cli (system-wide)..."
	if ! command -v wp > /dev/null 2>&1; then \
	    curl -fsLo /usr/local/bin/wp \
	        https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; \
	    chmod +x /usr/local/bin/wp; \
	    echo "  wp-cli installed"; \
	else \
	    echo "  wp-cli already present — upgrading"; \
	    wp --allow-root cli update --quiet 2>/dev/null || true; \
	fi
	$(HESTIA)/bin/h-add-sys-dependencies 2>/dev/null || true
	echo ""
	echo "[ OK ] add-tools complete (TOOLS_SET=$(TOOLS_SET))"
