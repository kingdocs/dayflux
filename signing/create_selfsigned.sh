#!/bin/bash
# 仅在证书丢失或过期时重新生成。
# ⚠️ 重新生成 = 换一张证书 = 应用身份改变，已授予的 TCC 权限会失效一次。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PASS="${DAYFLUX_P12_PASSWORD:-}"
if [ -z "$PASS" ] && [ -f "$ROOT/.p12-password" ]; then
  PASS="$(tr -d '\r\n' < "$ROOT/.p12-password")"
fi
if [ -z "$PASS" ]; then
  echo "缺少 p12 密码：设置 DAYFLUX_P12_PASSWORD，或创建 signing/.p12-password（该文件不入库）" >&2
  exit 1
fi

if [ -f "$ROOT/dayflux-selfsigned.p12" ]; then
  echo "证书已存在，未生成新证书。确需换证时先手动移走旧的 .p12 与 cert.pem。"
  exit 1
fi

TMP="$(mktemp -d /tmp/dayflux-cert.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out key.pem 2>/dev/null
cat > ext.cnf <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions   = v3_codesign
prompt            = no
[ dn ]
CN = Dayflux Code Signing
O  = Dayflux
OU = DAYFLUX
C  = CN
[ v3_codesign ]
basicConstraints     = critical,CA:FALSE
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning,1.2.840.113635.100.6.1.13
subjectKeyIdentifier = hash
EOF
openssl req -new -x509 -sha256 -days 3650 -key key.pem -out cert.pem \
  -config ext.cnf -extensions v3_codesign

# macOS security import 的兼容封装；否则报 MAC verification failed (wrong password?)
openssl pkcs12 -export -inkey key.pem -in cert.pem -out dayflux-selfsigned.p12 \
  -passout "pass:$PASS" -name "Dayflux Code Signing" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

cp cert.pem "$ROOT/cert.pem"
cp dayflux-selfsigned.p12 "$ROOT/dayflux-selfsigned.p12"
chmod 600 "$ROOT/dayflux-selfsigned.p12"
echo "已生成新证书（新身份）:"
openssl x509 -in "$ROOT/cert.pem" -noout -subject -dates -fingerprint -sha1
