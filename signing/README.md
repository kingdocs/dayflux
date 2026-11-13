# Dayflux 自签代码签名证书（已启用）

生成：2026-11-10 10:25｜**启用：2026-11-10 10:34（老板确认）**｜状态：`build.sh` 默认改用本证书签名，安装版与交付 zip 均已重签并实机复验。全程未导入登录钥匙串、未改动系统信任设置。

> 启用后的执行记录见文末第七节。第一至五节保留启用前的实验数据与判断（当时写「尚未启用」「本轮没擅自做」，仅描述那个时点的状态），数据本身仍然有效。

## 一、一句话结论

自签证书能解决的是「**每次重新编译，系统在权限眼里就换了一个 app**」；它解决不了 Gatekeeper、公证、Team ID。第一至五节是启用前的实验数据与判断（当时结论为「不是必须项」），最终于 10:34 经老板确认正式启用。

## 二、实测数据（本机 macOS 27.2 / 26B123）

| 项目 | ad-hoc（现状） | 自签（实验副本） |
|---|---|---|
| `codesign -dv` 签名 | `Signature=adhoc` | `Authority=DailyWall Self-Use Code Signing` |
| TeamIdentifier | not set | **not set（没变）** |
| Designated Requirement | `cdhash H"d24eaf39…"` | `identifier "local.dailywall.selfuse" and certificate root = H"09437db9…"` |
| 改动一个资源后重签的 DR | `cdhash H"f3875d65…"`（**变了**） | `certificate root = H"09437db9…"`（**不变**） |
| `codesign --verify --deep --strict` | 通过 | 通过 |
| `spctl -a -vvv -t execute` | rejected | **rejected**（`origin=DailyWall Self-Use Code Signing`） |
| `security find-identity -v -p codesigning` | 0 valid | 隔离钥匙串内 1 张，但标 `CSSMERR_TP_NOT_TRUSTED` |

对照经 Apple 正常签名的应用 DR（`anchor apple generic` + `certificate leaf[subject.OU]` 团队 ID）：差别在于 **Apple 根证书链 + 团队 ID**，自签证书拿不到，公证也拿不到。

## 三、能解决 / 不能解决

**能解决（唯一实质收益）**
- 把应用身份从「内容哈希」固定成「证书 + bundle id」。以后改代码、重新编译、重新打包，已授予的通知 / 自动化 / 辅助功能等 TCC 权限不会掉，LaunchServices 注册身份也稳定。
- `codesign -dv` 有明确的签名者，不再是 `adhoc`；排查问题时日志里的 `origin` 可读。

**不能解决**
- `spctl` / Gatekeeper 仍拒绝；没有 `anchor apple generic`、TeamIdentifier 仍 `not set`、无法公证、无法上架或对外分发。
- 不会让别的电脑直接信任这台机器签出的 app。

## 四、启用要付的代价（所以本轮没擅自做）

1. **签名身份会变一次**：从 ad-hoc 换成自签，等于系统眼里的「旧 app」变「新 app」，TCC 权限可能要重新授权一次。
2. **多一份要保管的东西**：`dailywall-selfsigned.p12` 含私钥，密码放在 `.p12-password`（两者都不入库），有效期至 **2036-11-07**。丢失或过期后重新生成 = 换身份，等于回到原点。换电脑、重装系统都要重新导入。
3. 每次 `./build.sh` 之后要多跑一次签名脚本，或者把构建脚本改成调用它。

## 五、文件清单

| 文件 | 说明 |
|---|---|
| `cert.pem` | 公钥证书，可公开，用于核对身份（SHA1 `09437DB96A8D050610799A0CE081590452A6E7A6`）；入库 |
| `dailywall-selfsigned.p12` | **含私钥，勿外传、不入库**；权限已设 600 |
| `.p12-password` | **p12 密码，不入库**；权限 600。脚本优先读环境变量 `DW_P12_PASSWORD`，其次读本文件，都没有则报错退出 |
| `sign_app.sh` | 给指定 `.app` 签名。全程用临时钥匙串，签完自动删除，不动系统钥匙串 |
| `create_selfsigned.sh` | 仅在证书丢失/过期时换证；已存在时会拒绝运行，防止误换身份 |

> 2026-11-10 备份到 GitHub 前，两个脚本里的硬编码密码已移除；仓库内不含任何 p12、私钥或密码。克隆到新机后需自行补回这两个文件，否则 `./build.sh` 会因缺少密码而失败（可用 `DW_SIGN_MODE=adhoc ./build.sh` 绕开自签）。

## 六、启用时的执行顺序（已于 2026-11-10 10:34 执行完毕）

1. `build.sh` 的默认签名分支改为调用 `sign_app.sh`，保留 `DW_SIGN_MODE=adhoc` 回退开关。
2. 完整重建 → 冒烟 20/20 → 连续重建两次确认 DR 与 cdhash 不变。
3. 温和退出旧进程（PID 57333）→ 旧安装版移到 `/tmp/DailyWall-adhoc-backup.app` → `ditto` 安装自签版 → `open` 启动。
4. 重打包 `Dayflux.zip`，解压回验签名、图标、无 quarantine。

## 七、启用后的实机验证（10:34—10:36）

| 检查项 | 结果 |
|---|---|
| 安装版签名 | `Authority=DailyWall Self-Use Code Signing`，`codesign --verify --deep --strict` 通过，DR = `certificate root H"09437db9…"` |
| 构建脚本 | `./build.sh` 连跑两次，DR 与 `CDHash=32244eb4…` 均一致 |
| 冒烟测试 | 20/20 全通过（含 6 项调度策略） |
| 实机启动 | 新进程 64112；元数据 866 B + UHD 3,556,980 B 成功；主窗口 430×560 在屏 |
| 偏好设置 | `autoDownload/autoChange=1`、`lastRunDate=20261110`、`showMenuBarIcon=0`，一项未改 |
| 重新打开入口 | `open -b local.dailywall.selfuse` → 日志「收到重新打开请求 → 显示主窗口」 |
| 交付包 | `Dayflux.zip` 1.2 MB，解压回验签名、图标、无 quarantine 均通过 |

**遗留边界（未变）**：`TeamIdentifier=not set`、`spctl -a` 仍 rejected、无 Apple 签发链、无法公证。属签名机制本身的限制，本机无解。

**回退**：`DW_SIGN_MODE=adhoc ./build.sh` 后用 `ditto` 覆盖安装版；或直接用 `/tmp/DailyWall-adhoc-backup.app`（临时备份，重启后可能被系统清理）。换身份会使已授予的 TCC 权限失效一次，需重新授权。
