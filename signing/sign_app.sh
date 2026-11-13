#!/bin/bash
# 用 Dayflux 自签代码签名证书（证书 CN 沿用旧名，换名即换身份）给指定 .app 签名。
# 特点：全程使用临时钥匙串，签名后自动删除，不改动登录钥匙串 / 系统信任设置。
# 用法：./sign_app.sh /path/to/Dayflux.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${1:-}"
[ -n "$APP" ] || { echo "用法: $0 <Dayflux.app 路径>"; exit 2; }
[ -d "$APP" ] || { echo "找不到 app: $APP"; exit 1; }

P12="$ROOT/dailywall-selfsigned.p12"
[ -f "$P12" ] || { echo "缺少证书: $P12"; exit 1; }

PASS="${DW_P12_PASSWORD:-}"
if [ -z "$PASS" ] && [ -f "$ROOT/.p12-password" ]; then
  PASS="$(tr -d '\r\n' < "$ROOT/.p12-password")"
fi
if [ -z "$PASS" ]; then
  echo "缺少 p12 密码：设置 DW_P12_PASSWORD，或创建 signing/.p12-password（该文件不入库）" >&2
  exit 1
fi
CERT="DailyWall Self-Use Code Signing"
TMP="$(mktemp -d /tmp/dw-sign.XXXXXX)"
KC="$TMP/Dayflux.keychain-db"

cleanup() {
  security delete-keychain "$KC" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

security create-keychain -p "$PASS" "$KC"
security unlock-keychain -p "$PASS" "$KC"
# p12 必须用 3DES/SHA1 封装，macOS 的 security import 不接受 OpenSSL 3+ 默认的 AES-256 封装
security import "$P12" -k "$KC" -P "$PASS" -T /usr/bin/codesign -A >/dev/null

# 自签证书没有 Apple 签发链，禁用 Apple 时间戳，避免联网等待
codesign --force --sign "$CERT" --keychain "$KC" \
  --identifier local.dailywall.selfuse --timestamp=none "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
echo "签名完成: $APP"
codesign -dr - "$APP" 2>&1 | grep 'designated =>' || true
