# libghostty-spm — dev surface. See README.md for the full story.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.PHONY: help hooks submodule build release
.DEFAULT_GOAL := help

help:
	@echo "libghostty-spm:"
	@echo "  make hooks      Install .githooks (one-time after clone)"
	@echo "  make submodule  Init/update vendor/ghostty to the pinned commit"
	@echo "  make build      Build dist/GhosttyKit.xcframework from source"
	@echo "  make release TAG=vX.Y.Z   Build, package, checksum, publish"

hooks:
	@git config core.hooksPath .githooks
	@echo "git hooks path set to .githooks/"

submodule:
	@git submodule update --init vendor/ghostty

build: submodule
	@./scripts/build-xcframework.sh

release: submodule
	@test -n "$(TAG)" || { echo "usage: make release TAG=vX.Y.Z" >&2; exit 1; }
	@./scripts/release.sh "$(TAG)"
