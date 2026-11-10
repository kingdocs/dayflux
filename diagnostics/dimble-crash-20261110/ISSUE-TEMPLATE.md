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
  every relaunch (6 crash reports within 20 minutes at 09:20, 09:22, 09:26,
  09:34 x2, 09:40 local time).
- All crashes are identical: EXC_BREAKPOINT (SIGTRAP), thread 0
  com.apple.main-thread, frame 0 = 0x1003bfa54 (in Dimble) + 2748,
  followed by libswift_Concurrency completeTaskWithClosure(...).
  No ASI, no NSException, not OOM, not killed by another process.
  atos cannot symbolicate the stripped release binary.

Relevant log lines (~/Library/Logs/Dimble/dimble.log)
  09:20:15.608  extras: add Pelmet.App.8FB44E86-08E6-4ACE-8295-FCBE5D70B1D0 → hidden
  09:22:32~09:23:34  extras: Pelmet.App.8FB44E86-… → show / hide (ghost) / fade (attached ahead) [repeated]
  09:22:44.699  apply: pending 1 move(s) + 0 trapped + 2 concealed = 3 — ...
                concealed=status:app.fif7y.Pelmet::Pelmet.App.8FB44E86-…
                [set=true listed=no remembered=none]
  09:23:15.817  extras: order slots repaired
  09:26:43.008  reveal: bar from display 2 (settingsPreview)
  09:26:43.111  crash

Notes
- The launcher item Dimble creates for itself appears never to register in
  the system's list (listed=no, remembered=none), so apply keeps re-asserting
  it until the Swift concurrency task traps.
- The target app's own NSStatusItem was removed (its "show menu bar icon"
  setting was OFF) for crashes #3-#6, and the crash still reproduces. So it
  does not depend on the target app owning a status item.
- Before the launcher was added, dozens of `reveal: bar from display 2
  (hover)` events in 09:00-09:19 caused no crash. There were no Dimble crash
  reports in ~/Library/Logs/DiagnosticReports before today.
- v0.3.4 release notes mention a similar "Dimble should no longer crash about
  2 seconds after launch, while it reads the menu bar" fix; this may be a
  regression or a second trigger path.

Attachments (in this zip)
- crash-reports/ : 6 original .ips reports
- dimble-log-excerpt.txt : key log lines, 09:19-09:35
- README-crash-report.md : full diagnosis (Chinese)
```
