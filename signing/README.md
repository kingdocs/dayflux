# Dayflux 代码签名

Dayflux 的 `.app` 需要签名才能在 macOS 上正常启动。仓库提供两种签名方式，都不需要 Apple Developer 账号。

## 方式一：ad-hoc 签名（第三方推荐）

```bash
DAYFLUX_SIGN_MODE=adhoc ./build.sh
```

`build.sh` 会用 `codesign -s -` 做 ad-hoc 签名并校验。仓库不分发任何私钥或密码，克隆后请显式使用这一方式。

## 方式二：自签证书（维护者本机）

在 `signing/` 下备齐 `dayflux-selfsigned.p12` 与 `.p12-password` 后，直接执行 `./build.sh` 即可，脚本会调用 `sign_app.sh`。

自己生成证书：

```bash
cd signing
DAYFLUX_P12_PASSWORD='<你的密码>' ./create_selfsigned.sh
```

脚本用 OpenSSL 生成一张 10 年有效期的代码签名证书（`CN = Dayflux Code Signing`），以 macOS `security import` 可接受的 3DES/SHA1 封装导出 p12，并把公钥证书写入 `cert.pem`。密码也可放在 `signing/.p12-password` 中，脚本优先读环境变量 `DAYFLUX_P12_PASSWORD`。

> **换证 = 换应用身份**：重新生成证书会改变 Designated Requirement，已授予的辅助功能等 TCC 权限会失效一次，需要重新授权。仅在证书丢失或过期时执行。

`sign_app.sh` 全程使用临时钥匙串，签名后自动删除，不改动登录钥匙串与系统信任设置；签名完成会执行 `codesign --verify --deep --strict`。

## 私钥与密码

| 文件 | 说明 |
|---|---|
| `dayflux-selfsigned.p12` | 含私钥，**不入库、不随仓库分发**，权限 600 |
| `.p12-password` | p12 密码，**不入库**，权限 600 |
| `cert.pem` | 公钥证书，入库仅供核对签名身份 |

`.gitignore` 已排除 `*.p12`、`.p12-password` 等凭据文件。克隆到新机后若未补回这两个文件，默认 `./build.sh` 会报缺少密码；请用方式一，或按方式二生成自己的证书。

## 边界

自签证书没有 Apple 签发链，`TeamIdentifier` 为 `not set`，`spctl -a` 仍会 rejected，也无法公证。它能解决的是「每次重新编译都被系统当成新 app」这一身份稳定性问题，不能替代 Developer ID 签名与公证；预编译包在别的机器上首次打开需要手动放行。这是自签机制的固有限制，不是代码缺陷。
