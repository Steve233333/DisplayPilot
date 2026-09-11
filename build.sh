#!/bin/bash
# 打一个可以发给别人的安装包：Release 编译 → 签名 → dist/DisplayPilot-<版本>.dmg + .zip
# 用法: ./build.sh [版本号]    （版本号默认取 Makefile 里的 MARKETING_VERSION）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DisplayPilot"
VERSION="${1:-1.0}"
CONFIG="Release"
DIST="dist"
DERIVED="build/DerivedData-release"

echo "==> 版本 $VERSION"
echo "==> 生成工程"
xcodegen generate >/dev/null

echo "==> 编译 Release"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" \
  build >/dev/null

APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
[ -d "$APP" ] || { echo "找不到 $APP"; exit 1; }

# Signing: use the local self-signed cert when present, otherwise fall back to ad-hoc.
# Both are unnotarized, so Gatekeeper treats them the same; the difference is whether
# an Accessibility grant survives future rebuilds.
IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Codex Patched Signing"; then
  IDENTITY="Codex Patched Signing"
fi
echo "==> 签名（$IDENTITY）"
codesign --force --deep --sign "$IDENTITY" "$APP"

echo "==> 打包"
rm -rf "$DIST"
mkdir -p "$DIST"

# ZIP（免安装）
ZIP="$DIST/${APP_NAME}-${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# DMG（拖进应用程序）
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO \
  "$DIST/${APP_NAME}-${VERSION}.dmg" >/dev/null
rm -rf "$STAGE"

echo
echo "==> 产物"
ls -lh "$DIST"
echo
echo "上传到 GitHub Release："
echo "  gh release create v$VERSION \"$DIST/${APP_NAME}-${VERSION}.dmg\" \"$DIST/${APP_NAME}-${VERSION}.zip\" --title \"v$VERSION\" --notes \"...\""

# 提交与推送（遵循仓库规则）
git add -A
git commit -q -m "chore: 发布 v$VERSION 安装包" 2>/dev/null || true
git push -q origin main 2>/dev/null || true
