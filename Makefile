APP_NAME := DisplayPilot
BUILD_DIR := build
CONFIG := Debug
# 本机用自制证书签名，保证辅助功能授权不会因为重编译失效；
# 没有这张证书时自动退回 ad-hoc 签名（别人拿去也能直接编）。
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q "Codex Patched Signing" && echo "Codex Patched Signing" || echo "-")

.PHONY: gen build sign run test clean install uninstall logs

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR)/DerivedData build | tail -20

sign: build
	@APP="$$(ls -d $(BUILD_DIR)/DerivedData/Build/Products/$(CONFIG)/$(APP_NAME).app)"; \
	echo "re-signing $$APP with '$(SIGN_IDENTITY)'"; \
	codesign --force --deep --sign "$(SIGN_IDENTITY)" "$$APP" && codesign -dv "$$APP" 2>&1 | head -4

run: sign
	@APP="$(BUILD_DIR)/DerivedData/Build/Products/$(CONFIG)/$(APP_NAME).app"; \
	pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true; \
	open "$$APP"; echo "launched $$APP"

stop:
	@pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" 2>/dev/null && echo "stopped" || echo "not running"

test: gen
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR)/DerivedData test | tail -25

clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(APP_NAME).xcodeproj
