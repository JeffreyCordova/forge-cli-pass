# SPDX-License-Identifier: Apache-2.0

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=

INSTALL = install
LN = ln
READLINK = readlink
RM = rm

SHELLCHECK ?= shellcheck
DASH ?= dash
BASH ?= bash
BUSYBOX ?= busybox

SOURCE_DIR := src
PROGRAMS := gh-pass glab-pass
SOURCES := $(addprefix $(SOURCE_DIR)/,$(PROGRAMS))
CI_SCRIPTS := ci/build-test-busybox.sh
SHELL_SOURCES := $(SOURCES) $(CI_SCRIPTS)

INSTALL_DIR := $(DESTDIR)$(BINDIR)
REPO_ROOT := $(shell pwd -P)

TEST_RUNNER := tests/run.sh

.PHONY: \
	all \
	check \
	lint \
	syntax-check \
	test \
	install \
	uninstall \
	dev-install \
	dev-uninstall

all: check

check: lint syntax-check test

lint:
	"$(SHELLCHECK)" --shell=sh $(SHELL_SOURCES)

syntax-check:
	"$(DASH)" -n $(SHELL_SOURCES)
	"$(BASH)" --posix -n $(SHELL_SOURCES)
	"$(BUSYBOX)" ash -n $(SHELL_SOURCES)

test:
	BUSYBOX="$(BUSYBOX)" MAKE="$(MAKE)" "$(TEST_RUNNER)"

install:
	$(INSTALL) -d "$(INSTALL_DIR)"
	@set -eu; \
	for program in $(PROGRAMS); do \
		$(INSTALL) -m 0755 \
			"$(SOURCE_DIR)/$$program" \
			"$(INSTALL_DIR)/$$program"; \
	done

uninstall:
	$(RM) -f -- \
		"$(INSTALL_DIR)/gh-pass" \
		"$(INSTALL_DIR)/glab-pass"

dev-install:
	$(INSTALL) -d "$(INSTALL_DIR)"
	@set -eu; \
	for program in $(PROGRAMS); do \
		source_path="$(REPO_ROOT)/$(SOURCE_DIR)/$$program"; \
		destination="$(INSTALL_DIR)/$$program"; \
		\
		if [ -L "$$destination" ]; then \
			if ! link_target=$$($(READLINK) -- "$$destination"); then \
				printf '%s\n' \
					"dev-install: failed to inspect symbolic link: $$destination" \
					>&2; \
				exit 1; \
			fi; \
			\
			if [ "$$link_target" = "$$source_path" ]; then \
				printf '%s\n' \
					"dev-install: already linked: $$destination"; \
				continue; \
			fi; \
			\
			printf '%s\n' \
				"dev-install: refusing to replace symbolic link: $$destination -> $$link_target" \
				>&2; \
			exit 1; \
		fi; \
		\
		if [ -e "$$destination" ]; then \
			printf '%s\n' \
				"dev-install: refusing to replace existing path: $$destination" \
				>&2; \
			exit 1; \
		fi; \
		\
		$(LN) -s -- "$$source_path" "$$destination"; \
	done

dev-uninstall:
	@set -u; \
	final_status=0; \
	\
	for program in $(PROGRAMS); do \
		source_path="$(REPO_ROOT)/$(SOURCE_DIR)/$$program"; \
		destination="$(INSTALL_DIR)/$$program"; \
		\
		if [ ! -e "$$destination" ] && [ ! -L "$$destination" ]; then \
			continue; \
		fi; \
		\
		if [ ! -L "$$destination" ]; then \
			printf '%s\n' \
				"dev-uninstall: retained non-symlink path: $$destination" \
				>&2; \
			final_status=1; \
			continue; \
		fi; \
		\
		if ! link_target=$$($(READLINK) -- "$$destination"); then \
			printf '%s\n' \
				"dev-uninstall: failed to inspect symbolic link: $$destination" \
				>&2; \
			final_status=1; \
			continue; \
		fi; \
		\
		if [ "$$link_target" != "$$source_path" ]; then \
			printf '%s\n' \
				"dev-uninstall: refusing to remove unrelated symbolic link: $$destination -> $$link_target" \
				>&2; \
			final_status=1; \
			continue; \
		fi; \
		\
		if ! $(RM) -f -- "$$destination"; then \
			printf '%s\n' \
				"dev-uninstall: failed to remove symbolic link: $$destination" \
				>&2; \
			final_status=1; \
		fi; \
	done; \
	\
	exit "$$final_status"
