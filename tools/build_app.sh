#!/usr/bin/env bash
#
# 打包 DeskPet 成可双击启动的 .app(未签名,本地用)
#
# 用法:
#   ./tools/build_app.sh
#
# 输出:
#   <project>/DeskPet.app
#
# 想签名(分发给别人):见脚本最下方注释

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DeskPet"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
BUNDLE_ID="dev.caleb.deskpet"

cd "$PROJECT_DIR"

# 1. Release 构建
echo "→ swift build -c release"
swift build -c release

# 找 binary 和 resource bundle(SPM 自动放在 .build 下)
BIN_PATH="$(swift build -c release --show-bin-path)"
BIN_FILE="$BIN_PATH/$APP_NAME"
# 资源 bundle 命名 = <Package>_<Target>.bundle
RES_BUNDLE="$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle"

if [[ ! -f "$BIN_FILE" ]]; then
    echo "✗ 找不到 binary: $BIN_FILE"
    exit 1
fi
if [[ ! -d "$RES_BUNDLE" ]]; then
    echo "✗ 找不到资源 bundle: $RES_BUNDLE"
    exit 1
fi

# 2. 清掉旧的,创建 .app 骨架
echo "→ 重建 $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. 拷 binary 和资源
cp "$BIN_FILE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
RES_BUNDLE_NAME="$(basename "$RES_BUNDLE")"
cp -R "$RES_BUNDLE/Resources/." "$APP_BUNDLE/Contents/Resources/"

# 4. 写 Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>DIY AI Desktop Pet</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>DeskPet needs Accessibility permission to locate your Claude Code/Codex window.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 5. 临时给本机签个 ad-hoc 签名(避免本机第一次启动被卡)
# 不使用 --deep: SwiftPM 的资源 .bundle 是扁平资源目录,不是可执行 bundle。
codesign --force --sign - "$APP_BUNDLE"

echo ""
echo "✓ 打包完成"
echo ""
echo "  路径:   $APP_BUNDLE"
echo "  启动:   open '$APP_BUNDLE'"
echo "  或者:   双击 Finder 里的 DeskPet.app"
echo ""
echo "  装到 Applications:"
echo "    mv '$APP_BUNDLE' /Applications/"
echo ""
echo "  第一次启动:"
echo "  - 本机:直接打开就能跑"
echo "  - 别的 Mac:Gatekeeper 会拦,右键 → 打开,选「仍要打开」"
echo "  - Accessibility 权限要重新授权(因为新二进制 = 新身份)"

# ─────────────────────────────────────────────
# 想升级到「签名版」?
# 1. 找你的开发者证书(BBnotes 上架那个):
#    security find-identity -p codesigning -v
# 2. 把上面 `codesign --sign -` 换成:
#    codesign --force --deep --options runtime \
#        --sign "Developer ID Application: 你的名字 (TEAMID)" \
#        "$APP_BUNDLE"
# 3. 想要完全无 Gatekeeper 摩擦(可分发):再加一步 notarytool 公证
#    xcrun notarytool submit "$APP_BUNDLE.zip" \
#        --apple-id <你的 Apple ID> --password <App 专用密码> \
#        --team-id <TEAMID> --wait
#    xcrun stapler staple "$APP_BUNDLE"
# ─────────────────────────────────────────────
