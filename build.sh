#!/bin/bash
# DailyWall 自用版构建脚本
# 只依赖 Xcode Command Line Tools：swiftc + plutil + codesign + security，不需要 Xcode.app。
# 默认用 signing/ 下的自签证书；DW_SIGN_MODE=adhoc 可临时回退到 ad-hoc 签名。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/DailyWall.app"
CONTENTS="$APP/Contents"
BIN="$CONTENTS/MacOS/DailyWall"

echo "==> 检查工具链"
command -v swiftc >/dev/null || { echo "缺少 swiftc，请先安装 Command Line Tools"; exit 1; }
command -v codesign >/dev/null || { echo "缺少 codesign"; exit 1; }
SDK="$(xcrun --show-sdk-path 2>/dev/null || true)"
[ -n "$SDK" ] || { echo "无法定位 macOS SDK"; exit 1; }
echo "    SDK: $SDK"

echo "==> 清理上一次的 app bundle（仅 build/DailyWall.app）"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"

echo "==> 编译 Swift 源码"
swiftc -O -swift-version 5 "$ROOT"/Sources/*.swift -o "$BIN"

echo "==> 组装 bundle"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
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

echo "==> 完成"
echo "    $APP"
echo "    运行: open \"$APP\""
