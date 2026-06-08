# HestiaRE Makefile

OS        ?= unknown
PROFILE   ?= standard
VERSION   := $(shell cat VERSION)

# OS abstraction
OS_CONF   := conf/os/$(OS).mk
-include $(OS_CONF)

.PHONY: install update status backup check-updates

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

status:
	@echo "HestiaRE $(VERSION) – status placeholder"

update:
	@echo "HestiaRE – update placeholder"

backup:
	@echo "HestiaRE – backup placeholder"