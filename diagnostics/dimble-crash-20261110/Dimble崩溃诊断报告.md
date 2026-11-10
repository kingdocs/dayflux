# Dimble 0.4.0-beta.2 崩溃诊断报告

生成时间：2026-11-10 09:44（GMT+8）｜诊断对象：老板本机，非公开发行环境

## 一、结论（先说结果）

**不是 DailyWall 的程序把 Dimble 弄崩了，但确实是「添加应用启动器」这一步触发了 Dimble 自身的 beta 缺陷。**

- 崩溃发生在 **Dimble 自己的主可执行文件**、主线程 `com.apple.main-thread`、Swift 并发回调内，异常为 `EXC_BREAKPOINT (SIGTRAP)`，属于典型的 Swift 断言／强制解包失败；无 NSException、无内存不足、无外部进程杀死。
- 6 次崩溃的崩溃地址**完全相同**（`0x1003bfa54 (in Dimble) + 2748`），是稳定的确定性缺陷，不是偶发。
- 触发条件与 Dimble **自己创建的启动器状态项**有关：它被反复 `show / hide (ghost) / fade (attached ahead)`，且 `apply` 时该状态项始终 `listed=no remembered=none`，书keeping 反复重放，最终触发断言。
- 09:26:44 及之后的崩溃发生时，DailyWall **已完全关闭自身菜单栏状态项**（`dw.showMenuBarIcon=0`，直到 09:38 才重新打开），Dimble 照样崩 —— 崩溃不依赖 DailyWall 的图标。

## 二、环境

| 项 | 值 |
|---|---|
| macOS | 27.2 (26B123) |
| Dimble | 0.4.0-beta.2，build 91，`app.fif7y.Pelmet`，`/Applications/Dimble.app` |
| 显示器 | 2 台（日志中 display 1 / display 2） |
| DailyWall | 本地 ad-hoc 签名、`LSUIElement` 后台应用，bundle id `local.dailywall.selfuse` |
| 最新版本核对 | GitHub Releases 最新为 `v0.4.0-beta.2`（2026-11-08），**尚无 beta.3**；稳定线最新为 `v0.3.5` |

## 三、崩溃清单

| # | 时间 | 崩溃进程 PID | 报告文件 |
|---|---|---|---|
| 1 | 09:20:33 | 47616 | Dimble-2026-11-10-092033.ips |
| 2 | 09:22:53 | 47836 | Dimble-2026-11-10-092253.ips |
| 3 | 09:26:44 | 48295 | Dimble-2026-11-10-092644.ips |
| 4 | 09:34:13 | — | Dimble-2026-11-10-093413.ips |
| 5 | 09:34:44 | — | Dimble-2026-11-10-093444.ips |
| 6 | 09:40:42 | — | Dimble-2026-11-10-094042.ips |

历史上 `~/Library/Logs/DiagnosticReports/` 中**无任何 Dimble 崩溃报告**；今天 6 次全部集中在添加启动器之后。

## 四、崩溃签名（6 份一致）

```
Exception Type:  EXC_BREAKPOINT (SIGTRAP)
Termination:     Namespace SIGNAL, Code 5, byProc "exc handler"
Faulting Thread: 0, queue com.apple.main-thread
Thread 0 frames:
  0  Dimble  0x1003bfa54  (+ 2748)      ← 崩溃指令
  1  Dimble  0x100011385
  2  Dimble  0x1000c273d
  3  Dimble  0x100011385
  4  libswift_Concurrency.dylib  completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*)
```

`atos` 在已 strip 的发行二进制上无法还原 Swift 符号名；`usedImages[0]` 为 `/Applications/Dimble.app/Contents/MacOS/Dimble`，可确认归属。

## 五、时间线与关键日志

```
09:19:59.280  extras: app picker (7 items)
09:20:15.608  extras: add Pelmet.App.8FB44E86-08E6-4ACE-8295-FCBE5D70B1D0 → hidden   ← 添加启动器到隐藏区
09:20:28.320  start: axTrusted=true canHide=true assignments=20                ← Dimble 本次启动
09:20:29.121  finished: boot picture taken (2 display(s), 19 hidden item(s))
09:20:31.143  reveal: bar from display 2 (hover)
09:20:31.318  *** CRASH #1 ***（启动后约 3 秒）
```

此后每次重启，启动器状态项持续高频切换：

```
09:22:32 / 09:22:42 / 09:22:44 / 09:23:28  extras: Pelmet.App.8FB44E86… → show
09:22:36 / 09:22:43 / 09:22:45 / 09:23:34  extras: Pelmet.App.8FB44E86… → hide (ghost)
09:22:44.699  apply: pending 1 move(s) + 0 trapped + 2 concealed = 3 — … concealed=status:app.fif7y.Pelmet::Pelmet.App.8FB44E86… [set=true listed=no remembered=none]
09:23:15.817  extras: order slots repaired
09:26:43.008  reveal: bar from display 2 (settingsPreview)
09:26:43.111  *** CRASH #3 ***
```

对照证据：

- 添加启动器**之前** 09:00–09:19，日志中有数十次 `reveal: bar from display 2 (hover)`，均未崩溃；说明单纯展开隐藏区不会崩。
- 09:26:44 崩溃时 DailyWall 自身状态项已移除（日志 `01:22:31Z 状态项未创建（显示菜单栏图标=关）`），Dimble 仍崩。
- 昨日 Dimble `v0.3.4` 的发布说明含：`Dimble should no longer crash about 2 seconds after launch, while it reads the menu bar.` —— 本次首次崩溃恰为启动后约 3 秒，属同类症状的回归或另一次触发路径。

## 六、本机止血建议（不改任何代码）

1. **移除触发条件（首选）**：Dimble 当前为退出状态。下次打开前，在 `设置 → 应用启动器` 中删除为 DailyWall 添加的那个启动器（`8FB44E86-…`），或把它从「隐藏区」移到「始终可见区」，避免 show/hide 反复切换。若一打开就崩，先保持退出即可。
2. **保持可用状态**：DailyWall 的「显示菜单栏图标」已重新开启，配合不启用 Dimble 隐藏功能或退出 Dimble，是昨晚与今早均已验证可用的组合（自动下载、08:30 自动换桌面、左键出主窗口均正常）。
3. **等上游修复**：GitHub 最新仍是 0.4.0-beta.2，暂无含修复的新 beta；可提交 issue 后等新版本，或按需退回稳定线 0.3.5（降级可能涉及配置兼容，建议先备份）。
4. **代码侧无需改动**：本次未修改 DailyWall 任何源码；重建 app 反而会改变 ad-hoc 签名身份，无益于该问题。

## 七、提交给 Dimble 作者的 Issue 模板（英文）

**Title**

```
[0.4.0-beta.2] EXC_BREAKPOINT at +0x3bfa54 after adding an App launcher for a locally built LSUIElement app
```

**Body**

```
Environment
- macOS 27.2 (26B123), Apple Silicon, 2 displays
- Dimble 0.4.0-beta.2 (build 91), app.fif7y.Pelmet
- Target app: locally built, ad-hoc signed, LSUIElement (menu-bar-only) app,
  bundle id local.dailywall.selfuse, no Developer ID / notarization

Steps to reproduce
1. Enable menu bar hiding (hidden section).
2. Settings > App launchers > add the locally built app; place the launcher
   item in the HIDDEN section.
3. Restart Dimble (or let it relaunch after a crash).

Result
- Crashes ~3 s after launch while reading the menu bar, then repeatedly on
  every relaunch (6 crash reports within 20 minutes).
- All crashes are identical: EXC_BREAKPOINT (SIGTRAP), thread 0
  com.apple.main-thread, frame 0 = 0x1003bfa54 (in Dimble) + 2748,
  followed by libswift_Concurrency completeTaskWithClosure(...).
  No ASI, no NSException, not OOM, not killed by another process.

Relevant log lines (~/Library/Logs/Dimble/dimble.log)
  extras: add Pelmet.App.8FB44E86-... → hidden
  extras: Pelmet.App.8FB44E86-... → show / hide (ghost) / fade (attached ahead)  [repeated]
  apply: pending 1 move(s) + 0 trapped + 2 concealed = 3 — ...
      concealed=status:app.fif7y.Pelmet::Pelmet.App.8FB44E86-... [set=true listed=no remembered=none]
  extras: order slots repaired
  reveal: bar from display 2 (settingsPreview)

Notes
- The launcher item Dimble creates for itself appears to never register in
  the system's list (listed=no, remembered=none), so apply keeps re-asserting
  it until the Swift concurrency task traps.
- The target app's own NSStatusItem was removed (its "show menu bar icon"
  setting was OFF) for crashes #3-#6; the crash still reproduces. So it does
  not depend on the target app owning a status item.
- v0.3.4 release notes mention a similar "crash about 2 seconds after launch,
  while it reads the menu bar" fix; this may be a regression.

Attachments: 6 .ips crash reports + dimble.log excerpt (see attached zip).
```

## 八、附件与隐私提示

- `crash-reports/`：6 份原始 `.ips` 崩溃报告
- `dimble-log-excerpt.txt`：09:19–09:35 关键日志摘录（221 行，按文件写入顺序，原日志时间戳不完全递增）
- `Dimble-crash-evidence-20261110.zip`：**全 ASCII 文件名**的证据包，可直接上传 GitHub Issue，内含 6 份 `.ips`、日志摘录、本报告副本 `README-crash-report.md`、以及可直接粘贴的英文 Issue 模板 `ISSUE-TEMPLATE.md`（内容同第七节）。中文版即本报告 `Dimble崩溃诊断报告.md`

⚠️ 日志摘录中包含本机已安装应用的 bundle id 与部分窗口标题，**外发前请自行过目一遍**，按需删减。
