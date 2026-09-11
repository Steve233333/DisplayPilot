APP_NAME := DisplayPilot
BUILD_DIR := build
CONFIG := Debug
SIGN_IDENTITY := Codex Patched Signing

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
