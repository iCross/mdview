# macOS Markdown Viewer - Makefile
# 使用 swiftc 編譯原生 macOS 應用程式

APP_NAME = mdviewer
SOURCES = Sources/main.swift \
          Sources/AppDelegate.swift \
          Sources/MarkdownRenderable.swift \
          Sources/MarkdownWindowController.swift \
          Sources/NativeMarkdownView.swift \
          Sources/ASTMarkdownRenderer.swift \
          Sources/IncrementalSyntaxHighlighter.swift \
          Sources/FileHandler.swift \
          Sources/MenuBuilder.swift

FRAMEWORKS = -framework AppKit

# 編譯旗標
DEBUG_FLAGS = -g -Onone
RELEASE_FLAGS = -O -whole-module-optimization

.PHONY: all debug release clean run run-empty run-ci run-empty-ci test smoke help

# 預設目標：Debug 版本
all: debug

# Debug 版本
debug: $(SOURCES)
	@echo "🔨 編譯 Debug 版本..."
	@perl -e 'alarm shift; exec @ARGV' 300 swift build -c debug --product $(APP_NAME)
	@cp -f .build/debug/$(APP_NAME) ./$(APP_NAME)
	@# macOS Gatekeeper 在部分環境會拒絕執行未簽章二進制；用 ad-hoc sign 確保可在測試/子行程中正常啟動
	@/usr/bin/codesign --force --sign - ./$(APP_NAME)
	@echo "✅ 編譯完成: ./$(APP_NAME)"

# Release 版本
release: $(SOURCES)
	@echo "🚀 編譯 Release 版本..."
	@perl -e 'alarm shift; exec @ARGV' 300 swift build -c release --product $(APP_NAME)
	@cp -f .build/release/$(APP_NAME) ./$(APP_NAME)
	@/usr/bin/codesign --force --sign - ./$(APP_NAME)
	@echo "✅ 編譯完成: ./$(APP_NAME)"

# 清除編譯產物
clean:
	@echo "🧹 清除編譯產物..."
	@# 用 trash 移到 macOS Trash；路徑不存在時不要讓 make 失敗
	@if [ -e "./$(APP_NAME)" ]; then trash "./$(APP_NAME)"; fi
	@if [ -d ".build" ]; then trash ".build"; fi
	@echo "✅ 清除完成"

# 執行應用程式（使用測試檔案；互動式，預期會常駐）
run: debug
	@echo "▶️ 執行應用程式..."
	@./$(APP_NAME) Fixtures/test.md

# 執行應用程式（無檔案；互動式，預期會常駐）
run-empty: debug
	@echo "▶️ 執行應用程式（無檔案）..."
	@./$(APP_NAME)

# 執行應用程式（CI/自動化用：加 timeout 避免卡住）
run-ci: debug
	@echo "▶️ 執行應用程式（CI timeout 30s）..."
	@perl -e 'alarm shift; exec @ARGV' 30 ./$(APP_NAME) Fixtures/test.md

run-empty-ci: debug
	@echo "▶️ 執行應用程式（無檔案；CI timeout 30s）..."
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
	@echo "  make run-ci   - 編譯並執行（使用 test.md；timeout 30s）"
	@echo "  make run-empty-ci - 編譯並執行（無檔案；timeout 30s）"
	@echo "  make test     - 執行測試"
	@echo ""
	@echo "執行方式:"
	@echo "  ./$(APP_NAME) path/to/file.md"
