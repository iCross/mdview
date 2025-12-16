# macOS Markdown Viewer - Makefile
# Build the native macOS app with Swift

APP_NAME = mdview
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

.PHONY: all debug release clean run run-empty run-ci run-empty-ci test smoke help

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

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@# Move to macOS Trash; don't fail if a path doesn't exist.
	@if [ -e "./$(APP_NAME)" ]; then trash "./$(APP_NAME)"; fi
	@if [ -e "./mdviewer" ]; then trash "./mdviewer"; fi
	@if [ -d ".build" ]; then trash ".build"; fi
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
	@echo "  make clean        - Clean build artifacts"
	@echo "  make run          - Build & run (with Fixtures/test.md)"
	@echo "  make run-empty    - Build & run (no file)"
	@echo "  make run-ci       - Build & run (with Fixtures/test.md; timeout 30s)"
	@echo "  make run-empty-ci - Build & run (no file; timeout 30s)"
	@echo "  make test         - Run tests"
	@echo ""
	@echo "Running:"
	@echo "  ./$(APP_NAME) path/to/file.md"
