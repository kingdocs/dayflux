# DailyWall（自用版 1.1.2）

**完全自用，不公开发布。** macOS 菜单栏应用，获取 Bing 每日壁纸、保存到自选目录、设为桌面。

## 主界面

![DailyWall 主界面（2026-11-10 实机截图）](tools/main-window.png)

> 预览区为当日 Bing 壁纸实图；四个按钮依次为 设置桌面 / 下载壁纸 / 打开目录 / 清洁键盘。窗口右下角页脚是版本号、构建日期与当天编译序号、作者署名。此截图仅用于本仓库的界面说明，不对外分发。

## 系统要求与构建

- 实测环境：macOS 27.2 (26B123)、Apple Silicon、Xcode **Command Line Tools**（无需 Xcode.app、无需 Apple Developer 账号）。
- 构建：

  ```bash
  ./build.sh
  open build/DailyWall.app
  ```

  脚本用 `swiftc` 编译 `Sources/*.swift`，组装 `.app`，`plutil -lint` 校验，最后用 `signing/` 下的自签证书签名并做严格校验。产物不带 `com.apple.quarantine`。需要临时回退到 ad-hoc 签名时：`DW_SIGN_MODE=adhoc ./build.sh`。
- 产物位置：`build/DailyWall.app`。重复构建只覆盖该 bundle，不触碰其它目录。

## 版本号与构建序号

- 主界面右下角显示版本、构建信息与作者署名，例如 `V1.1.2(20261110.2)@Micheas` 表示：软件版本 1.1.2，2026-11-10 当天第 2 次成功编译，作者 @Micheas。
- 版本号在 `build.sh` 顶部 `APP_VERSION`、署名在 `AUTHOR_TAG` 各一处维护；每次 `./build.sh` **成功**后按当天日期自动累加序号，跨天归 1，构建失败不计数（下次仍用同一号）。
- 序号存本机 `.buildcounter`（不入库，换机从 1 开始）；`build/generated/BuildInfo.swift` 由脚本生成，界面页脚与 `Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion` 使用同一份值。

## 代码签名（2026-11-10 起启用自签）

- 默认用自签证书 `DailyWall Self-Use Code Signing`（SHA1 `09437DB96A8D050610799A0CE081590452A6E7A6`，有效期至 2036-11-07）。证书、私钥、脚本与完整实测结论见 `signing/README.md`。
- 应用身份固定为 `identifier "local.dailywall.selfuse" and certificate root H"09437db9…"`；**连续两次完整重建实测 cdhash 与身份完全一致**，重建不再让 TCC／LaunchServices 把它当成新 app。
- 签名脚本用临时钥匙串，签完即删，不改动登录钥匙串与系统信任设置；`codesign --verify --deep --strict` 通过。
- 边界：无 Apple 签发链、TeamIdentifier 仍 `not set`、`spctl -a` 仍 rejected、无法公证。完全自用不受影响；拷到别的机器仍需对方自行信任，不要对外分发。
- `signing/dailywall-selfsigned.p12` **含私钥，勿外传**；丢失后重新生成等于换身份。回退方式：`DW_SIGN_MODE=adhoc ./build.sh`。

## 已安装与交付

- **已安装**：`/Applications/DailyWall.app`（系统级「应用程序」目录，自签版，2026-11-10 13:20 从 `~/Applications` 迁移至此并重启；LaunchServices 已重新注册 `local.dailywall.selfuse` → 新路径），可在访达「应用程序」或启动台直接双击。
- **可拷走的交付包**：`DailyWall.zip`（约 1.2 MB，含程序图标）。用 `ditto -c -k --sequesterRsrc --keepParent` 打包；已验证解压后 `codesign -v` 通过、`Authority=DailyWall Self-Use Code Signing`、无 `com.apple.quarantine`。
- 自签版实机启动已验证：元数据 866 B + UHD 图 3,556,980 B 拉取成功、主窗口 430×560 正常、偏好与 `lastRunDate` 未变、`open -b` 重新打开入口正常唤出主窗口。
- 替换前的 ad-hoc 版本备份在 `/tmp/DailyWall-adhoc-backup.app`（临时目录，重启后可能被系统清理）；长期回退路径是源码 + `DW_SIGN_MODE=adhoc`。
- **窗口行为**：主窗口仅保留「关闭」按钮（无最小化 / 缩放）；从菜单栏图标打开时，窗口出现在鼠标光标附近（光标下方、水平居中并约束在所在屏幕可见区域内，不再固定屏幕中央）。

## 程序图标

- `AppIcon.icns`（10 种尺寸 16→1024）由 `tools/make_icons.swift` 纯 CoreGraphics 矢量绘制，`./build.sh` 自动嵌入 `Contents/Resources`，`Info.plist` 以 `CFBundleIconFile` 引用。用于访达、启动台、关于窗口。
- 设计：黄昏渐变天空 + 日轮 + 双层山脊 + 水面倒影 + 星点 + 圆角细白描边，呼应「每日壁纸」。预览 `tools/appicon_preview.png`。
- 菜单栏状态项是**另一套单色模板图**（相框 + 日轮 + 山脊，`isTemplate = true`），由系统按明暗模式自动着色，与 App 图标同一视觉语言。A/B 证据：`tools/menubar_final.png`（运行，最左侧出现该图标）、`tools/menubar_without_app.png`（退出后消失）。
- 重新生成图标：

  ```bash
  mkdir -p /tmp/dw_iconbuild && cp tools/make_icons.swift /tmp/dw_iconbuild/main.swift
  swiftc -O -swift-version 5 /tmp/dw_iconbuild/main.swift -o /tmp/make_icons
  /tmp/make_icons AppIcon.iconset
  iconutil -c icns AppIcon.iconset -o AppIcon.icns
  ./build.sh
  ```

  注意脚本含顶层代码，编译前必须复制成名为 `main.swift` 的文件。

## 首次使用

1. 启动后应用只驻留菜单栏、不弹主窗口；左键点菜单栏图标调出主界面，顶部会提示「首次使用请选择保存目录」。默认建议目录是 `~/Pictures/DailyWall`；点「选择目录」可改。
2. 目录只授权给这一个路径。应用**不会**删除、移动、重命名目录里的任何文件，也不做缓存清理到该目录。
3. **左键点击菜单栏图标直接打开主窗口**；右键才弹出菜单（今日标题、立即下载、立即设置桌面、设置、退出）。关闭主窗口不会退出应用。

## 界面与操作

| 区域 | 行为 |
|---|---|
| 预览 | 16:9，展示当日壁纸；加载中／失败有独立状态与「重试」。预览失败不影响下载 |
| 标题 | 直接显示接口 `title`；字段缺失时整行隐藏，不以版权说明代替 |
| 辅助信息 | `Bing · 生效日期 · 实际像素`，像素来自下载后解析，不是 UHD 标签 |
| 设置桌面 | 必要时先下载成品，再应用到**所有已连接显示器** |
| 下载壁纸 | 同日同地区文件已存在时默认跳过；覆盖前会弹窗取得本次确认 |
| 打开目录 | 在 Finder 中显示成品文件（不存在则显示目录） |
| 三行设置 | 点击打开设置面板 |

设置面板分组：**菜单栏**（置顶，含「显示菜单栏图标」开关）、来源与清晰度、下载与保存、自动化、通知与启动、隐私与缓存。

- **「完成」按钮固定在顶部**：不随内容滚动，任何位置都能直接关闭设置面板；也支持 Esc 关闭。
- **说明改为问号气泡**（2026-11-10）：每个分组标题后有一个圆形 `?` 图标，点击弹出白色圆角气泡说明（参照 AlDente 样式，箭头指向图标）；界面不再常驻灰色小字，视觉更简洁。再点图标或点别处即可收起。

## 菜单栏交互

| 操作 | 结果 |
|---|---|
| 左键点击 DailyWall 菜单栏图标 | **直接显示主窗口**，不弹菜单、不用在菜单项里选 |
| 右键点击（或 Control + 左键） | 弹出菜单：打开主窗口、今日标题、立即下载、立即设置桌面、设置…、退出 |
| 从启动台 / 访达双击打开 | 直接显示主窗口（`applicationShouldHandleReopen` 无条件 `showWindow()`） |

应用启动后**不弹主窗口**，只驻留菜单栏；需要时点图标调出。设置面板最上方「菜单栏」分组有 **「显示菜单栏图标」** 开关（偏好键 `dw.showMenuBarIcon`，默认开）。关闭时用 `NSStatusBar.removeStatusItem` 彻底移除状态项；关闭后仍可从主窗口任意一行设置里改回来，或从访达双击打开应用。

**实测验证（2026-11-10）**：辅助功能接口按下状态项触发「左键 → 显示主窗口」；`open -b local.dailywall.selfuse` 触发「收到重新打开请求 → 显示主窗口」；关闭开关后日志为「状态项未创建」且 AX 查询 `AXExtrasMenuBar` 返回 `-25212`（系统里确实没有状态项）；日志 `/tmp/dw_status.log` 亦记录了「右键 → 弹出菜单」分支。

## 自动化口径

- 应用常驻期间用「单次定时器」挂到下一次该执行的时刻（**取代每分钟轮询**，2026-11-10 优化）；到达设定时间且当天尚未**成功**执行时，按 `autoDownload` / `autoChange` 执行。每天主线程最多唤醒 1~2 次（成功则挂到次日同一时刻；失败按 5 分钟冷却重试）。系统睡眠期间定时器不计时，唤醒后若错过时间点会在 15 秒稳定期结束后补触发，睡眠补偿不再依赖轮询。
- **`lastRunDate` 只在核心链路全部成功后写入**（2026-11-10 修复）：元数据获取、下载（或按规则跳过）、设置桌面任一步失败，当天标记保持为空，**5 分钟后自动重试，直到当天成功**；不再出现「失败一次、整天不补」。
- **桌面设置必须回读确认**（2026-11-11 修复）：`setDesktopImageURL` 在系统刚唤醒／刚登录时可能「不抛错但不生效」。旧实现只要没抛错就判成功并写下当天标记，导致**整天不再更新**。现在对全部已连接显示器设置后回读主屏壁纸 URL 比对文件名，最多校验 3 次；未生效即判失败，进入 5 分钟重试链。
- **启动／唤醒稳定期**（2026-11-11）：冷启动延后 10 秒、系统唤醒延后 15 秒再补跑，避开 WindowServer / Dock / 桌面 Space 未就绪的窗口。稳定期只推迟「立即补跑」，不影响当天设定时刻与次日触发点。
- 调度逻辑抽为纯函数：`SchedulePolicy.shouldRun`（是否该执行）与 `SchedulePolicy.nextFire`（下一次触发时刻），均位于 `Sources/Models.swift`；冒烟覆盖 `shouldRun` 的 6 种情形（到点／未到点／当天已成功／冷却中／冷却结束／跨日补偿）以及 `nextFire` 的 8 个分支（已完成→次日、未到→当天、错过→即补、冷却中→+5min、冷却过→即补、稳定期推迟、稳定期不影响次日、稳定期不影响当天）。
- 主窗口关闭后释放预览图与缓存的原图数据（常驻不再占用解码位图内存）；重新打开窗口时从磁盘缓存秒回，不联网。
- 每日时间的「分」按 **5 分钟刻度**选择（00、05、…、55）；历史非整 5 分的值会在启动时自动规整到最近的下整刻度。
- 关机、睡眠、强制退出期间无法保证准点；**恢复运行后按当前日期补偿一次，不追溯多日**（以 `lastRunDate` 判定）。
- 调度日志：`/tmp/dw_schedule.log`，记录「下次调度检查 / 开始当天任务 / 桌面校验第 N 次是否生效 / 任务成功写入标记 / 任务失败等待重试」。
- 未安装 LaunchAgent：菜单栏应用本身常驻，LaunchAgent 的「应用未运行也能触发」优势在此不成立，且未公证应用安装 LaunchAgent 会增加不确定性。登录启动通过 `SMAppService` 注册。
- 桌面设置失败不会删除已下载文件。

## 文件、缓存与错误

- 文件名：`DailyWall_<enddate>_zh-CN.jpg`，`enddate` 取 Bing 生效日；`idx=0&n=1` 固定，绝不为补齐历史请求其它日期。
- 下载流程：临时文件原子写入 → JPEG 解码校验 → 原子移入目标，不产生伪完整成品。
- 缓存仅在 `~/Library/Caches/DailyWall`，文件名以 `dw_` 开头；「清理应用缓存」只删这些文件，**不触碰保存目录**。
- 错误提示同时说明发生了什么、可执行的动作、以及是否影响已有文件（一律不影响）。

## 使用边界（重要）

- 接口返回自带声明：「下载今日美图。**仅限用作桌面壁纸**。」
- 仅限自用：**不打包图片进发行物、不用于宣传截图、不商用、不再分发**。壁纸版权归原权利人所有。
- `HPImageArchive.aspx` 属非正式使用方式，随时可能变化。服务层已协议隔离，变化时应先重跑 `tools/verify_bing.py` 并更新 `M0_接口核验记录.md`。
- 本目录下的 `tools/preview_sample.jpg` 只是界面示意素材，**不进入 app bundle**。

## 已知限制

| 项 | 说明 |
|---|---|
| 图形界面 | 目录/通知授权弹窗、桌面是否真的更换、VoiceOver 表现，仍需实机人工确认 |
| 签名 | 自签代码签名证书（2026-11-10 起）。身份固定、重建不丢权限；但无 Apple 信任链与 Team ID，`spctl` 仍 rejected、不能公证、不能对外分发（签名机制限制，本机无解）。见「代码签名」一节 |
| 通知 | 默认关闭；系统拒绝授权或未签名环境不可用时静默降级为应用内状态提示，不影响下载与换桌面 |
| 登录启动 | 通过 `SMAppService`，注册失败仅提示一次，不反复弹窗 |
| 地区 | 已砍掉。实测 `mkt` 单独传入不改变返回内容；固定中文、固定 `zh-CN` 请求 |
| 兼容性 | 只在 macOS 27.2 单台设备验证，未做跨版本兼容测试 |
| 窗口缩放 | 主窗口固定宽度 430pt，未做缩放适配；预览区固定 398×224（16:9），与参考稿的卡片式设计一致 |
| 定时调度 | 2026-11-10 08:46 实机验证通过：自动生成 `DailyWall_20261110_zh-CN.jpg`。10:08 端到端复验「失败当天不重试」修复：清空标记后重启 → 日志显示任务成功 → 才写回 `lastRunDate=20261110`；该次 `applyDesktop()` 亦返回成功（桌面视觉是否更换仍需肉眼确认） |
| 不进 Dock | 按老板要求保持 `LSUIElement = true` + `.accessory`，不做 Dock 常驻。关闭主窗口后，从启动台/访达再次双击图标可唤出主窗口，或左键点菜单栏图标 |

## 网络通道与诊断

- 元数据与图片默认走 `URLSession`，显式禁用系统代理直连；单次超时 8 秒（图片 12 秒）。
- 任一层失败时自动切换 `/usr/bin/curl --noproxy '*'` 备用通道。实测同一 GUI bundle 内 curl 直连 0.27 秒返回 200。
- 诊断日志：`/tmp/dw_app_net.log`（网络）、`/tmp/dw_status.log`（状态项生命周期与左右键分支）、`/tmp/dw_schedule.log`（自动任务成功／失败与重试）。首次启动曾出现 `NSURLErrorTimedOut`，加入备用通道后元数据 888 字节、UHD 图片 3,664,513 字节均正常返回。
- 复核工具：

  ```bash
  # 核心链路 + 调度策略冒烟测试（20 项，含 6 项调度策略）
  swiftc -O -swift-version 5 Sources/Models.swift Sources/Services.swift tools/smoke/Smoke.swift -o /tmp/dw_smoke && /tmp/dw_smoke
  # 网络出口探针（模拟无代理环境变量）
  swiftc -O -swift-version 5 -parse-as-library tools/NetProbe.swift -o /tmp/dw_netprobe
  env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy /tmp/dw_netprobe
  ```

- 界面截图：**`tools/main-window.png`（当前主界面，含版本页脚与「清洁键盘」按钮，已入库供本文档展示）**、`tools/preview_final.png`（早期主窗口，真实 Bing 当日图）、`tools/settings_v3.png`（新版设置面板：顶部完成按钮 + 问号图标，无常驻小字）、`tools/settings_help_popover.png`（点击问号弹出的说明气泡）、`tools/settings_menubar_toggle.png`（含「菜单栏」分组的旧版设置面板）。
- 调试入口：`open build/DailyWall.app --args --show-settings`。注意在部分启动方式下 `open` 不把参数传给进程（2026-11-10 实测发生过，日志里的启动参数可核对），此时从主窗口任意一行设置点进设置面板即可。
- 设置面板用 `HelpButton`（`questionmark.circle` + `.popover`）承载分组说明；纯 Command Line Tools 下 SwiftUI 的 `@State` 宏插件不可用，弹窗状态改用 `ObservableObject` + `@StateObject`。外层 `ScrollView` 只在内容超高时滚动，顶部完成按钮始终固定。

## 与规格书的差异（自用定位下的裁剪）

对照 `DailyWall_软件开发需求规格说明书.md`：

- 删除：Developer ID 签名与公证、沙盒要求、MIT/LICENSE/第三方声明/隐私说明、M4 发布准备、验收 10／11、地区选择与地区显示。**保留**自签代码签名（仅稳定本机身份，不用于分发，见「代码签名」一节）。
- 简化：目录授权由 Security-Scoped Bookmark 改为保存用户明确选择的路径（自用不启用沙盒）；设置页入口放菜单栏；调度用常驻 Timer 而非 LaunchAgent。
- 保留：文件责任边界、缓存隔离、原子写入、冲突跳过与覆盖确认、仅当天、错误状态、UHD 拼接规则、动态标题、真实像素显示。

## 仓库与备份（2026-11-10）

- 私有仓库：`https://github.com/kingdocs/DailyWall`（账号 `kingdocs`，**private**），用途仅为工程与代码备份，不公开发布。
- **入库范围**：Swift 源码、`build.sh` / `Info.plist`、自签脚本与公钥证书、M0 核验工具与记录、图标源资产（`AppIcon.iconset` / `AppIcon.icns`）。
- **未入库**（见 `.gitignore`）：
  - `signing/dailywall-selfsigned.p12`（私钥）与 `signing/.p12-password`（密码）—— 换机需自行补回，否则构建会报缺少密码；可用 `signing/create_selfsigned.sh` 重新生成（等于换身份）。
  - `build/`、`DailyWall.zip`、`*.app`（构建产物，可重建）。
  - `tools/` 下**历史**界面截图与 `preview_sample.jpg`（仅本机留存，不入库）；唯一例外是 `tools/main-window.png`，即本文档「主界面」一节用到的实机截图。Bing 每日壁纸为微软免费开放内容，此处仅作自用界面说明；仍不打包进发行物、不商用、不对外分发。
- 仓库以 `DailyWall/` 为根，工作区上层的 `.workbuddy/`（会话与记忆文件）不在仓库内。
- 克隆到新机后：`./build.sh` 即可构建。若要沿用同一张自签证书，先补回 p12 与密码文件；否则用 `DW_SIGN_MODE=adhoc ./build.sh` 走 ad-hoc 签名。

## 复核

```bash
python3 tools/verify_bing.py --json tools/m0_result.json
```

每次接口结构变化、跨 UTC 16:00 切换点、更换网络出口或发版前，应重跑并向 `M0_接口核验记录.md` **追加**新记录，不覆盖既有结论。
