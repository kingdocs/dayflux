# Dayflux

> **Dayflux — Fresh wallpaper, every day.**
>
> 主界面标题行在 `Dayflux` 后紧跟短式 ` - Fresh wallpaper, every day.`（小号次要色文字，2026-11-13 加）。

**开源、免费、MIT 许可。** macOS 菜单栏应用，获取 Bing 每日壁纸、保存到自选目录、设为桌面。当前版本 **1.2.2**，构建标识 `V1.2.2(20261115.3)@Micheas`。

## 开源与版权

- **代码**：本仓库自 **2026-11-15** 起公开，采用 **MIT License**（见 [`LICENSE`](LICENSE)）。允许使用、复制、修改、合并、发布与分发（含商用），只需保留版权与许可声明；软件按「原样」提供，不作任何担保。
- **壁纸图片**：每日壁纸来自 Bing 每日图片接口，接口自带「**仅限用作桌面壁纸**」声明，图片版权归原权利人（微软及其图片提供方）所有。本仓库与发行包**不打包任何壁纸图片**；程序只在运行时按该声明把图片下载到使用者本机，用作桌面壁纸。图片不随代码再分发、不用于商业宣传。
- **本文档截图**：`tools/main-window.png` 是实机界面截图，内含当日 Bing 壁纸的缩略显示，仅用于说明界面，不作为图片素材提供。
- **预编译二进制**：GitHub Release 中的 `.zip` 是维护者本机自签的包，未公证、无 Apple 信任链，第三方首次打开需在「系统设置 → 隐私与安全性」自行允许，或右键「打开」；更推荐克隆源码自行构建签名（见下节）。签名私钥与密码**不随仓库分发**。
- 项目按个人日常使用场景设计，代码公开欢迎 issue / PR，但不承诺支持节奏与响应时间。

## 主界面

![Dayflux 主界面（2026-11-15 实机截图）](tools/main-window.png)

> 预览区为当日 Bing 壁纸实图；四个按钮依次为 设置桌面 / 下载壁纸 / 打开目录 / 清洁键盘。窗口右下角页脚是版本号、构建日期与当天编译序号、作者署名。截图中的壁纸缩略图仅作界面说明，版权归原权利人。

## 系统要求与构建

- 实测环境：macOS 27.2 (26B123)、Apple Silicon、Xcode **Command Line Tools**（无需 Xcode.app、无需 Apple Developer 账号）。
- 克隆后构建（**第三方请用 ad-hoc 签名**，仓库不含签名私钥）：

  ```bash
  git clone https://github.com/kingdocs/dayflux.git
  cd dayflux
  DW_SIGN_MODE=adhoc ./build.sh
  open build/Dayflux.app
  ```

  维护者本机保存有自签证书时可省略环境变量，直接 `./build.sh`。脚本用 `swiftc` 编译 `Sources/*.swift`，组装 `.app`，`plutil -lint` 校验，最后签名并做严格校验；产物不带 `com.apple.quarantine`。
- 产物位置：`build/Dayflux.app`。重复构建只覆盖该 bundle，不触碰其它目录。
- 想使用自己的签名身份，可用 `signing/create_selfsigned.sh` 生成证书（等价于换一个应用身份），详见 `signing/README.md`。

## 版本号与构建序号

- 主界面右下角显示版本、构建信息与作者署名，例如 `V1.2.2(20261115.3)@Micheas` 表示：软件版本 1.2.2，2026-11-15 当天第 3 次成功编译，作者 @Micheas。
- **三段语义化版本规则（2026-11-15 定）**：第 1 位是**大版本号**，有新增功能或大的功能性升级时修改；第 2 位用于**小的功能性调整**；第 3 位**只在纯 BUG 修复时**修改。`1.2.1` 即因「缓存目录被系统清理后全天自动任务失败」这一纯 BUG 修复从 `1.2.0` 升位；`1.2.2` 按 2026-11-15 的项目裁定，缓存目录改名视为该修复的收尾，沿用第 3 位（规则例外，已记录）。
- **版本历史**：`1.1.2` 修复唤醒后设桌面静默失败；`1.2.0` 更名 Dayflux + 设置面板单列定稿 + slogan + 壁纸前缀改 `Dayflux_`；`1.2.1`（2026-11-15）修复缓存目录被系统清理后全天自动任务失败，属纯 BUG 修复；`1.2.2`（2026-11-15）缓存目录由 `~/Library/Caches/DailyWall` 改为 `~/Library/Caches/Dayflux`，属 1.2.1 修复收尾。**2026-11-15 仓库公开并采用 MIT 许可**，属文档与许可变更，未改软件版本。各版本的完整发布说明见 [GitHub Releases](https://github.com/kingdocs/dayflux/releases)。
- 版本号在 `build.sh` 顶部 `APP_VERSION`、署名在 `AUTHOR_TAG` 各一处维护；每次 `./build.sh` **成功**后按当天日期自动累加序号，跨天归 1，构建失败不计数（下次仍用同一号）。
- 序号存构建机的 `.buildcounter`（不入库，换机从 1 开始）；`build/generated/BuildInfo.swift` 由脚本生成，界面页脚与 `Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion` 使用同一份值。

## 代码签名（2026-11-10 起启用自签）

- 维护者本机默认用自签证书 `DailyWall Self-Use Code Signing`（SHA1 `09437DB96A8D050610799A0CE081590452A6E7A6`，有效期至 2036-11-07）。证书、脚本与完整实测结论见 `signing/README.md`；**私钥不入库、不随仓库分发**。
- 应用身份固定为 `identifier "local.dailywall.selfuse" and certificate root H"09437db9…"`；**连续两次完整重建实测 cdhash 与身份完全一致**，重建不再让 TCC／LaunchServices 把它当成新 app（仅对持有该私钥的机器成立）。
- 签名脚本用临时钥匙串，签完即删，不改动登录钥匙串与系统信任设置；`codesign --verify --deep --strict` 通过。
- 边界：无 Apple 签发链、TeamIdentifier 仍 `not set`、`spctl -a` 仍 rejected、无法公证。这是自签机制的固有限制，不是代码缺陷。第三方请用 `DW_SIGN_MODE=adhoc ./build.sh` 自行签名，或改用自己生成的证书。
- `signing/dailywall-selfsigned.p12` 含私钥，**不入库**；丢失后重新生成等于换身份。克隆后若无该私钥，默认 `./build.sh` 会报缺少密码，请显式指定 ad-hoc 模式。

## 安装与发行

- **安装**：把 `Dayflux.app` 拖入 `/Applications`（或任意位置）后双击启动。`LSUIElement=true`，应用不进 Dock，启动后只驻留菜单栏、不弹主窗口；左键菜单栏图标调出主界面，或从访达 / 启动台双击图标唤出。
- **预编译包**：各版本资产为 `Dayflux-<版本>-macos.zip`，用 `ditto -c -k --sequesterRsrc --keepParent` 打包（不用 `zip -r`，会破坏 bundle 签名结构）。已验证解压后 `codesign -v` 通过、无 `com.apple.quarantine`；**自签未公证**，第三方使用前请自行放行，或按上节自行构建。
- **自签版实机启动已验证**：元数据 866 B + UHD 图 3,556,980 B 拉取成功、主窗口 430×560 正常、偏好与 `lastRunDate` 未变、`open -b` 重新打开入口正常唤出主窗口。
- **窗口行为**：主窗口仅保留「关闭」按钮（无最小化 / 缩放）；从菜单栏图标打开时，窗口出现在鼠标光标附近（光标下方、水平居中并约束在所在屏幕可见区域内，不再固定屏幕中央）。

## 程序图标

- `AppIcon.icns`（10 种尺寸 16→1024）由 `tools/make_icons.swift` 纯 CoreGraphics 矢量绘制，`./build.sh` 自动嵌入 `Contents/Resources`，`Info.plist` 以 `CFBundleIconFile` 引用。用于访达、启动台、关于窗口。
- 设计：黄昏渐变天空 + 日轮 + 双层山脊 + 水面倒影 + 星点 + 圆角细白描边，呼应「每日壁纸」。预览 `tools/appicon_preview.png`。
- 菜单栏状态项是**另一套单色模板图**（相框 + 日轮 + 山脊，`isTemplate = true`），由系统按明暗模式自动着色，与 App 图标同一视觉语言。
- 重新生成图标：

  ```bash
  mkdir -p /tmp/dw_iconbuild && cp tools/make_icons.swift /tmp/dw_iconbuild/main.swift
  swiftc -O -swift-version 5 /tmp/dw_iconbuild/main.swift -o /tmp/make_icons
  /tmp/make_icons AppIcon.iconset
  iconutil -c icns AppIcon.iconset -o AppIcon.icns
  DW_SIGN_MODE=adhoc ./build.sh
  ```

  注意脚本含顶层代码，编译前必须复制成名为 `main.swift` 的文件。

## 首次使用

1. 启动后应用只驻留菜单栏、不弹主窗口；左键点菜单栏图标调出主界面，顶部会提示「首次使用请选择保存目录」。默认建议目录是 `~/Pictures/Dayflux`（仅作用于偏好为空的首次运行）；应用**不会**自动迁移、重命名或删除已有壁纸文件；点「选择目录」可改。
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

设置面板为**上下单列**布局（2026-11-13 定稿）：6 组依次为菜单栏图标、清晰度、自动下载与保存目录、定时更换、通知与登录启动、缓存清理。宽度 430 与主窗口一致，**一屏完整显示、无滚动条**，窗口尺寸 430×498。

- **已去掉 6 个分类标题**（2026-11-13 简化）：控件本身自解释，分组说明改由每组首行控件旁的 `?` 图标承载，点击弹出气泡；再点图标或点别处收起。
- **「完成」按钮固定在顶部**：面板无滚动区域，按钮始终可见；也支持 Esc 关闭。

## 菜单栏交互

| 操作 | 结果 |
|---|---|
| 左键点击 Dayflux 菜单栏图标 | **直接显示主窗口**，不弹菜单、不用在菜单项里选 |
| 右键点击（或 Control + 左键） | 弹出菜单：打开主窗口、今日标题、立即下载、立即设置桌面、设置…、退出 |
| 从启动台 / 访达双击打开 | 直接显示主窗口（`applicationShouldHandleReopen` 无条件 `showWindow()`） |

应用启动后**不弹主窗口**，只驻留菜单栏；需要时点图标调出。设置面板最上方「菜单栏」分组有 **「显示菜单栏图标」** 开关（偏好键 `dw.showMenuBarIcon`，默认开）。关闭时用 `NSStatusBar.removeStatusItem` 彻底移除状态项；关闭后仍可从主窗口任意一行设置里改回来，或从访达双击打开应用。

**实测验证（2026-11-10）**：辅助功能接口按下状态项触发「左键 → 显示主窗口」；`open -b local.dailywall.selfuse` 触发「收到重新打开请求 → 显示主窗口」；关闭开关后日志为「状态项未创建」且 AX 查询 `AXExtrasMenuBar` 返回 `-25212`；日志 `/tmp/dw_status.log` 亦记录了「右键 → 弹出菜单」分支。

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

- 文件名：`Dayflux_<enddate>_zh-CN.jpg`，`enddate` 取 Bing 生效日；`idx=0&n=1` 固定，绝不为补齐历史请求其它日期。
- 下载流程：临时文件原子写入 → JPEG 解码校验 → 原子移入目标，不产生伪完整成品。
- 缓存仅在 `~/Library/Caches/Dayflux`（1.2.2 起，旧名 `DailyWall` 已弃用），文件名仍以 `dw_` 开头（内部标识保留）；「清理应用缓存」只删这些文件，**不触碰保存目录**。旧目录 `~/Library/Caches/DailyWall` 不自动迁移、不删除，由系统自行清理。
- **缓存目录自愈（2026-11-15 修复）**：系统会清理 `~/Library/Caches` 下的目录，旧版只在单例初始化时建一次，目录消失后写缓存抛 `NSCocoaErrorDomain code=4`，连带预览、下载、设桌面全部失败并每 5 分钟重试。现在每次写入前自动重建目录；缓存写入失败只记日志并降级为纯内存，图片已在内存中，主流程不受影响。
- 错误提示同时说明发生了什么、可执行的动作、以及是否影响已有文件（一律不影响）。

## 图片来源与使用边界

- 接口返回自带声明：「下载今日美图。**仅限用作桌面壁纸**。」
- 壁纸图片版权归原权利人所有。程序仅按上述声明在运行时下载到使用者本机用作桌面壁纸；仓库与发行包不打包壁纸图片，README 截图中的缩略显示仅作界面说明，不作素材分发或商业宣传。
- `HPImageArchive.aspx` 属非正式使用方式，随时可能变化。服务层已协议隔离，变化时应先重跑 `tools/verify_bing.py` 并更新 `M0_接口核验记录.md`。
- `tools/preview_sample.jpg` 只是界面示意素材，未入库、不进入 app bundle。

## 已知限制

| 项 | 说明 |
|---|---|
| 图形界面 | 目录/通知授权弹窗、桌面是否真的更换、VoiceOver 表现，仍需实机人工确认 |
| 签名 | 预编译包为维护者本机自签，无 Apple 信任链与 Team ID，`spctl` 仍 rejected、不能公证；第三方请自行允许或克隆后 ad-hoc 自签。见「代码签名」一节 |
| 通知 | 默认关闭；系统拒绝授权或未签名环境不可用时静默降级为应用内状态提示，不影响下载与换桌面 |
| 登录启动 | 通过 `SMAppService`，注册失败仅提示一次，不反复弹窗 |
| 地区 | 已砍掉。实测 `mkt` 单独传入不改变返回内容；固定中文、固定 `zh-CN` 请求 |
| 兼容性 | 只在 macOS 27.2 单台设备验证，未做跨版本兼容测试 |
| 窗口缩放 | 主窗口固定宽度 430pt，未做缩放适配；预览区固定 398×224（16:9），与参考稿的卡片式设计一致 |
| 定时调度 | 2026-11-10 08:46 实机验证通过：自动生成 `DailyWall_20261110_zh-CN.jpg`（当时前缀；2026-11-13 起新文件改为 `Dayflux_`）。10:08 端到端复验「失败当天不重试」修复：清空标记后重启 → 日志显示任务成功 → 才写回 `lastRunDate=20261110`；该次 `applyDesktop()` 亦返回成功（桌面视觉是否更换仍需肉眼确认） |
| 不进 Dock | 按项目设计保持 `LSUIElement = true` + `.accessory`，不做 Dock 常驻。关闭主窗口后，从启动台/访达再次双击图标可唤出主窗口，或左键点菜单栏图标 |

## 网络通道与诊断

- 元数据与图片默认走 `URLSession`，显式禁用系统代理直连；单次超时 8 秒（图片 12 秒）。
- 任一层失败时自动切换 `/usr/bin/curl --noproxy '*'` 备用通道。实测同一 GUI bundle 内 curl 直连 0.27 秒返回 200。
- 诊断日志：`/tmp/dw_app_net.log`（网络）、`/tmp/dw_status.log`（状态项生命周期与左右键分支）、`/tmp/dw_schedule.log`（自动任务成功／失败与重试）。首次启动曾出现 `NSURLErrorTimedOut`，加入备用通道后元数据 888 字节、UHD 图片 3,664,513 字节均正常返回。
- 复核工具：

  ```bash
  # 核心链路 + 调度策略 + 缓存自愈冒烟测试（37 项，含 9 项缓存相关）
  swiftc -O -swift-version 5 Sources/Models.swift Sources/Services.swift tools/smoke/Smoke.swift -o /tmp/dw_smoke && /tmp/dw_smoke
  # 网络出口探针（模拟无代理环境变量）
  swiftc -O -swift-version 5 -parse-as-library tools/NetProbe.swift -o /tmp/dw_netprobe
  env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy /tmp/dw_netprobe
  ```

- 界面截图：仓库内唯一入库的是 **`tools/main-window.png`**（当前主界面，含版本页脚与「清洁键盘」按钮，供本文档展示）；其余历史界面截图未入库。
- 调试入口：`open build/Dayflux.app --args --show-settings`。注意在部分启动方式下 `open` 不把参数传给进程（2026-11-10、11-13 均实测发生过，日志里的启动参数可核对）；此时直接运行 `build/Dayflux.app/Contents/MacOS/Dayflux --show-settings` 可确保参数生效，或从主窗口任意一行设置点进设置面板。
- 设置面板用 `HelpButton`（`questionmark.circle` + `.popover`）承载分组说明；纯 Command Line Tools 下 SwiftUI 的 `@State` 宏插件不可用，弹窗状态改用 `ObservableObject` + `@StateObject`。2026-11-13 起**移除 `ScrollView`**，改为上下单列 + `.fixedSize(vertical: true)`，一屏完整显示；并去掉 6 个分类标题，把问号说明移到每组首行控件旁，视图理想高度 430×498；顶部「完成」按钮始终可见。

## 与规格书的差异（轻量定位下的裁剪）

对照 `DailyWall_软件开发需求规格说明书.md`：

- 删除：Developer ID 签名与公证、沙盒要求、第三方声明/隐私说明文档、M4 发布准备、验收 10／11、地区选择与地区显示。**2026-11-15 起补回 MIT LICENSE**（见 `LICENSE`）。**保留**自签代码签名（仅稳定维护者本机身份，第三方请自行签名，见「代码签名」一节）。
- 简化：目录授权由 Security-Scoped Bookmark 改为保存用户明确选择的路径（轻量定位，不启用沙盒）；设置页入口放菜单栏；调度用常驻 Timer 而非 LaunchAgent。
- 保留：文件责任边界、缓存隔离、原子写入、冲突跳过与覆盖确认、仅当天、错误状态、UHD 拼接规则、动态标题、真实像素显示。

## 仓库与开源（2026-11-10 建库，2026-11-15 公开）

- **公开仓库**：https://github.com/kingdocs/dayflux （MIT License，2026-11-15 由 private 改为 public）。欢迎使用源码、提交 issue / PR。旧名 `kingdocs/DailyWall` 由 GitHub 自动重定向。
- **更名（2026-11-13）**：项目由 `DailyWall` 正式更名为 **Dayflux**，slogan 为 `Dayflux — Fresh wallpaper, every day.`；仓库 `kingdocs/DailyWall` → `kingdocs/dayflux`，工程目录 `DailyWall/` → `dayflux/`，应用 `DailyWall.app` → `Dayflux.app`，界面与文档品牌名统一为 Dayflux，版本升至 1.2.0。**内部标识保持不变**：bundle id `local.dailywall.selfuse`、`dw.*` 偏好键、窗口 autosave key、自签证书 CN `DailyWall Self-Use Code Signing`。**例外（2026-11-15 定，1.2.2 起）**：缓存目录由 `~/Library/Caches/DailyWall` 改为 `~/Library/Caches/Dayflux`；它只是临时缓存，改名不影响偏好与 TCC 授权，旧目录不自动迁移、不删除，由系统清理。**壁纸文件名前缀自 2026-11-13 起改为 `Dayflux_`**（新下载文件为 `Dayflux_<日期>_zh-CN.jpg`），此前保存的历史文件仍用 `DailyWall_` 旧名、不重命名。默认保存目录为 `~/Pictures/Dayflux`（仅作用于偏好为空的首次运行）。理由：改 bundle id 会丢偏好与 TCC 授权，改证书 CN 等于换签名身份；登录启动 `SMAppService.mainApp` 按 bundle id 注册，不受 app 改名影响。
- **入库范围**：Swift 源码、`build.sh` / `Info.plist`、自签脚本与公钥证书、`LICENSE`、M0 核验工具与记录、图标源资产（`AppIcon.iconset` / `AppIcon.icns`）、`tools/main-window.png`。
- **未入库**（见 `.gitignore`）：
  - `signing/dailywall-selfsigned.p12`（私钥）与 `signing/.p12-password`（密码）—— **不随仓库分发**；第三方请用 `DW_SIGN_MODE=adhoc ./build.sh`，或用 `signing/create_selfsigned.sh` 生成自己的证书。
  - `build/`、`Dayflux.zip`、`*.app`（构建产物，可重建）。
  - `tools/` 下历史界面截图与 `preview_sample.jpg`；唯一入库的界面截图是 `tools/main-window.png`，内含当日 Bing 壁纸的缩略显示，仅用于说明界面。
- 仓库以 `dayflux/` 为根。克隆到新机后按「系统要求与构建」一节操作即可；`./build.sh` 的默认签名路径需要维护者本机的私钥，第三方请显式指定 ad-hoc 模式。

## 复核

```bash
python3 tools/verify_bing.py --json tools/m0_result.json
```

每次接口结构变化、跨 UTC 16:00 切换点、更换网络出口或发版前，应重跑并向 `M0_接口核验记录.md` **追加**新记录，不覆盖既有结论。
