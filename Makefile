# macOS Markdown Viewer - Makefile
# Build the native macOS app with Swift

APP_NAME = mdview
GH_REPO ?=
GH_REPO_FROM_PUBLIC = $$(git remote get-url public 2>/dev/null | sed -E 's|^git@github.com:||; s|^https://github.com/||; s|\.git$$||')
TAG ?= $(shell git describe --tags --exact-match 2>/dev/null || true)
VERSION ?= $(if $(TAG),$(TAG),$(shell git rev-parse --short HEAD 2>/dev/null || echo dev))
ARCH ?= $(shell uname -m)
DIST_DIR = dist
RELEASE_ARCHIVE = $(DIST_DIR)/$(APP_NAME)-$(VERSION)-macos-$(ARCH).tar.gz
SOURCES = Sources/main.swift \
          Sources/AppDelegate.swift \
          Sources/MarkdownRenderable.swift \
          Sources/MarkdownWindowController.swift \
          Sources/NativeMarkdownView.swift \
          Sources/ASTMarkdownRenderer.swift \
          Sources/MermaidRenderer.swift \
          Sources/RemoteImageAttachment.swift \
          Sources/FileHandler.swift \
          Sources/MenuBuilder.swift

FRAMEWORKS = -framework AppKit

# Build flags
DEBUG_FLAGS = -g -Onone
RELEASE_FLAGS = -O -whole-module-optimization

.PHONY: all debug release dist github-release github-release-upload check-github-release clean run run-empty run-ci run-empty-ci test smoke help

# Default target: Debug
all: debug

# Debug
debug: $(SOURCES)
	@echo "🔨 Building Debug..."
	@perl -e 'alarm shift; exec @ARGV' 300 swift build -c debug --product $(APP_NAME)
	@# macOS Gatekeeper may refuse to run unsigned binaries in some environments; use ad-hoc signing so tests/subprocesses can launch.
	@# Note: the swift build product may rely on SPM resource bundles next to it. So we do not copy the binary to repo root.
	@# Instead, we sign the .build product and create a symlink at repo root (./mdview -> .build/.../mdview).
	@/usr/bin/codesign --force --sign - .build/debug/$(APP_NAME)
	@ln -sf .build/debug/$(APP_NAME) ./$(APP_NAME)
	@echo "✅ Built: ./$(APP_NAME)"

# Release
release: $(SOURCES)
	@echo "🚀 Building Release..."
	@perl -e 'alarm shift; exec @ARGV' 300 swift build -c release --product $(APP_NAME)
	@/usr/bin/codesign --force --sign - .build/release/$(APP_NAME)
	@ln -sf .build/release/$(APP_NAME) ./$(APP_NAME)
	@echo "✅ Built: ./$(APP_NAME)"

# Package the release binary for GitHub Releases
dist: release
	@echo "📦 Packaging $(RELEASE_ARCHIVE)..."
	@mkdir -p "$(DIST_DIR)"
	@tmp_dir=$$(mktemp -d); \
	trap 'trash "$$tmp_dir" >/dev/null 2>&1 || true' EXIT; \
	package_dir="$(APP_NAME)-$(VERSION)-macos-$(ARCH)"; \
	mkdir -p "$$tmp_dir/$$package_dir"; \
	cp ".build/release/$(APP_NAME)" "$$tmp_dir/$$package_dir/$(APP_NAME)"; \
	cp "README.md" "$$tmp_dir/$$package_dir/README.md"; \
	tar -czf "$(RELEASE_ARCHIVE)" -C "$$tmp_dir" "$$package_dir"
	@echo "✅ Packaged: $(RELEASE_ARCHIVE)"

check-github-release:
	@if [ -z "$(TAG)" ]; then \
		echo "Set TAG, for example: make github-release TAG=v0.1.0"; \
		exit 1; \
	fi
	@repo="$(GH_REPO)"; \
	if [ -z "$$repo" ]; then repo="$(GH_REPO_FROM_PUBLIC)"; fi; \
	if [ -z "$$repo" ]; then \
		echo "Set GH_REPO=owner/repo or configure a public remote"; \
		exit 1; \
	fi
	@command -v gh >/dev/null || { echo "gh is required"; exit 1; }
	@gh auth status >/dev/null

# Create a GitHub Release and upload the packaged binary.
# This uses gh's Release API. It does not run git push to the public remote.
github-release: check-github-release dist
	@repo="$(GH_REPO)"; \
	if [ -z "$$repo" ]; then repo="$(GH_REPO_FROM_PUBLIC)"; fi; \
	echo "🚀 Creating GitHub release $(TAG)..."; \
	gh release create "$(TAG)" "$(RELEASE_ARCHIVE)#$(APP_NAME) macOS $(ARCH)" \
		--repo "$$repo" \
		--target "$$(git rev-parse HEAD)" \
		--generate-notes

# Upload or replace the packaged binary on an existing GitHub Release.
github-release-upload: check-github-release dist
	@repo="$(GH_REPO)"; \
	if [ -z "$$repo" ]; then repo="$(GH_REPO_FROM_PUBLIC)"; fi; \
	echo "⬆️ Uploading $(RELEASE_ARCHIVE) to release $(TAG)..."; \
	gh release upload "$(TAG)" "$(RELEASE_ARCHIVE)#$(APP_NAME) macOS $(ARCH)" \
		--repo "$$repo" \
		--clobber

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@# Move to macOS Trash; don't fail if a path doesn't exist.
	@if [ -e "./$(APP_NAME)" ]; then trash "./$(APP_NAME)"; fi
	@if [ -e "./mdviewer" ]; then trash "./mdviewer"; fi
	@if [ -d ".build" ]; then trash ".build"; fi
	@if [ -d "$(DIST_DIR)" ]; then trash "$(DIST_DIR)"; fi
	@echo "✅ Clean complete"

# Run (with a fixture file; interactive; expected to stay running)
run: debug
	@echo "▶️ Running app..."
	@./$(APP_NAME) Fixtures/test.md

# Run (no file; interactive; expected to stay running)
run-empty: debug
	@echo "▶️ Running app (no file)..."
	@./$(APP_NAME)

# Run (CI/automation: add timeout to avoid hanging)
run-ci: debug
	@echo "▶️ Running app (CI timeout 30s)..."
	@perl -e 'alarm shift; exec @ARGV' 30 ./$(APP_NAME) Fixtures/test.md

run-empty-ci: debug
	@echo "▶️ Running app (no file; CI timeout 30s)..."
	@perl -e 'alarm shift; exec @ARGV' 30 ./$(APP_NAME)

# Run tests (ensure the binary is up-to-date first)
test: debug
	@echo "🧪 Running tests..."
	@perl -e 'alarm shift; exec @ARGV' 120 swift Tests/test_runner.swift

# GUI smoke test (avoid hanging)
smoke: debug
	@echo "🫧 Running GUI smoke test..."
	@perl -e 'alarm shift; exec @ARGV' 10 ./$(APP_NAME) --smoke-test

# Help
help:
	@echo "macOS Markdown Viewer - Build commands"
	@echo ""
	@echo "Usage:"
	@echo "  make              - Build Debug"
	@echo "  make debug        - Build Debug"
	@echo "  make release      - Build Release"
	@echo "  make dist         - Build Release and package dist archive"
	@echo "  make github-release TAG=v0.1.0 - Create GitHub Release with gh"
	@echo "  make github-release-upload TAG=v0.1.0 - Upload archive to an existing GitHub Release"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make run          - Build & run (with Fixtures/test.md)"
	@echo "  make run-empty    - Build & run (no file)"
	@echo "  make run-ci       - Build & run (with Fixtures/test.md; timeout 30s)"
	@echo "  make run-empty-ci - Build & run (no file; timeout 30s)"
	@echo "  make test         - Run tests"
	@echo ""
	@echo "Running:"
	@echo "  ./$(APP_NAME) path/to/file.md"
