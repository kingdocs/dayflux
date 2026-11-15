#!/bin/bash
# Dayflux 自用版构建脚本
# 只依赖 Xcode Command Line Tools：swiftc + plutil + codesign + security，不需要 Xcode.app。
# 默认用 signing/ 下的自签证书；DW_SIGN_MODE=adhoc 可临时回退到 ad-hoc 签名。
set -euo pipefail

# 软件版本号（三段语义化，升级版本只改这里）：
#   第 1 位 大版本号：新增功能或大的功能性升级时修改
#   第 2 位 功能位：小的功能性调整时修改
#   第 3 位 修复位：纯 BUG 修复时修改
# 构建序号按「当天第 N 次成功构建」自动累加，最终显示格式
# 为 V1.2.2(20261115.3)，即 20261115 当天第 3 次编译。
APP_VERSION="1.2.2"

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Dayflux.app"
CONTENTS="$APP/Contents"
BIN="$CONTENTS/MacOS/Dayflux"

echo "==> 检查工具链"
command -v swiftc >/dev/null || { echo "缺少 swiftc，请先安装 Command Line Tools"; exit 1; }
command -v codesign >/dev/null || { echo "缺少 codesign"; exit 1; }
SDK="$(xcrun --show-sdk-path 2>/dev/null || true)"
[ -n "$SDK" ] || { echo "无法定位 macOS SDK"; exit 1; }
echo "    SDK: $SDK"

echo "==> 生成版本信息"
TODAY="$(date +%Y%m%d)"
COUNTER_FILE="$ROOT/.buildcounter"
LAST_DATE=""
LAST_SEQ=0
if [ -f "$COUNTER_FILE" ]; then
  read -r LAST_DATE LAST_SEQ < "$COUNTER_FILE" || true
fi
LAST_DATE="${LAST_DATE:-}"
LAST_SEQ="${LAST_SEQ:-0}"
case "$LAST_SEQ" in ''|*[!0-9]*) LAST_SEQ=0 ;; esac
if [ "$LAST_DATE" = "$TODAY" ]; then
  BUILD_SEQ=$((LAST_SEQ + 1))
else
  BUILD_SEQ=1
fi
BUILD_TAG="${TODAY}.${BUILD_SEQ}"
# 作者署名：跟在版本号后面一起显示。
AUTHOR_TAG='@Micheas'
BUILD_DISPLAY="V${APP_VERSION}(${BUILD_TAG})${AUTHOR_TAG}"
GEN_DIR="$ROOT/build/generated"
mkdir -p "$GEN_DIR"
cat > "$GEN_DIR/BuildInfo.swift" <<EOF
// 由 build.sh 自动生成，请勿手工编辑；build/ 不纳入版本控制。
enum BuildInfo {
    static let version = "${APP_VERSION}"
    static let buildTag = "${BUILD_TAG}"
    static let author = "${AUTHOR_TAG}"
    static let display = "V${APP_VERSION}(${BUILD_TAG})${AUTHOR_TAG}"
}
EOF
echo "    ${BUILD_DISPLAY}"

echo "==> 清理上一次的 app bundle（仅 build/Dayflux.app）"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"

echo "==> 编译 Swift 源码"
swiftc -O -swift-version 5 "$ROOT"/Sources/*.swift "$GEN_DIR/BuildInfo.swift" -o "$BIN"

echo "==> 组装 bundle"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_TAG" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"
if [ -f "$ROOT/AppIcon.icns" ]; then
  mkdir -p "$CONTENTS/Resources"
  cp "$ROOT/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
  echo "    AppIcon.icns 已嵌入 bundle"
fi
plutil -lint "$CONTENTS/Info.plist"

echo "==> 代码签名（默认用 signing/ 下的自签证书；DW_SIGN_MODE=adhoc 可临时回退）"
if [ "${DW_SIGN_MODE:-selfsigned}" = "adhoc" ]; then
  codesign -s - --force --identifier local.dailywall.selfuse "$APP"
  codesign -v --verbose=2 "$APP"
else
  "$ROOT/signing/sign_app.sh" "$APP"
fi

# 只有完整构建成功才累加序号，失败的下次仍用同一个号。
printf '%s %s\n' "$TODAY" "$BUILD_SEQ" > "$COUNTER_FILE"

echo "==> 完成"
echo "    $APP"
echo "    $BUILD_DISPLAY"
echo "    运行: open \"$APP\""
