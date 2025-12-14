# macOS Markdown Viewer - Makefile
# 使用 swiftc 編譯原生 macOS 應用程式

APP_NAME = mdviewer
SOURCES = Sources/main.swift \
          Sources/AppDelegate.swift \
          Sources/MarkdownView.swift \
          Sources/NativeMarkdownView.swift \
          Sources/FileHandler.swift \
          Sources/MenuBuilder.swift

FRAMEWORKS = -framework AppKit -framework WebKit

# 編譯旗標
DEBUG_FLAGS = -g -Onone
RELEASE_FLAGS = -O -whole-module-optimization

.PHONY: all debug release clean run run-empty test smoke help

# 預設目標：Debug 版本
all: debug

# Debug 版本
debug: $(SOURCES)
	@echo "🔨 編譯 Debug 版本..."
	@perl -e 'alarm shift; exec @ARGV' 300 swift build -c debug --product $(APP_NAME)
	@cp -f .build/debug/$(APP_NAME) ./$(APP_NAME)
	@echo "✅ 編譯完成: ./$(APP_NAME)"

# Release 版本
release: $(SOURCES)
	@echo "🚀 編譯 Release 版本..."
	@perl -e 'alarm shift; exec @ARGV' 300 swift build -c release --product $(APP_NAME)
	@cp -f .build/release/$(APP_NAME) ./$(APP_NAME)
	@echo "✅ 編譯完成: ./$(APP_NAME)"

# 清除編譯產物
clean:
	@echo "🧹 清除編譯產物..."
	trash -F $(APP_NAME)
	trash -F .build
	@echo "✅ 清除完成"

# 執行應用程式（使用測試檔案）
run: debug
	@echo "▶️ 執行應用程式..."
	@perl -e 'alarm shift; exec @ARGV' 30 ./$(APP_NAME) test.md

# 執行應用程式（無檔案參數）
run-empty: debug
	@echo "▶️ 執行應用程式（無檔案）..."
	@perl -e 'alarm shift; exec @ARGV' 30 ./$(APP_NAME)

# 執行測試（先確保 binary 為最新）
test: debug
	@echo "🧪 執行測試..."
	@perl -e 'alarm shift; exec @ARGV' 120 swift Tests/test_runner.swift

# GUI smoke test（避免卡住）
smoke: debug
	@echo "🫧 執行 GUI smoke test..."
	@perl -e 'alarm shift; exec @ARGV' 10 ./$(APP_NAME) --smoke-test

# 顯示幫助
help:
	@echo "macOS Markdown Viewer - 建置指令"
	@echo ""
	@echo "使用方式:"
	@echo "  make          - 編譯 Debug 版本"
	@echo "  make debug    - 編譯 Debug 版本"
	@echo "  make release  - 編譯 Release 版本"
	@echo "  make clean    - 清除編譯產物"
	@echo "  make run      - 編譯並執行（使用 test.md）"
	@echo "  make run-empty- 編譯並執行（無檔案）"
	@echo "  make test     - 執行測試"
	@echo ""
	@echo "執行方式:"
	@echo "  ./$(APP_NAME) path/to/file.md"
