import AppKit
import ApplicationServices
import Combine
import Foundation
import SwiftUI

/// 状态项诊断日志（仅写入 /tmp，不触碰用户目录）。
private func dwStatusLog(_ message: String) {
    let line = "\(Date().ISO8601Format()) \(message)\n"
    let path = "/tmp/dw_status.log"
    guard let data = line.data(using: .utf8) else { return }
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

/// CGEvent 回调是 C 函数指针，不能捕获 self；用文件级全局保存 tap 引用，
/// 便于 tap 被系统超时禁用时重新启用。
private var gCleaningTap: CFMachPort?
private var gCleaningSystemEventLogCount = 0

/// 清洁期间绝对不能吞鼠标事件，否则无法点「结束清洁」按钮解除。
/// 这些是鼠标/指针/滚轮/平板事件类型（CGEventType rawValue），
/// 订阅掩码取它们的补集，鼠标根本不进回调，最安全。
private let kPointerEventTypes: [UInt32] = [1, 2, 3, 4, 5, 6, 7, 22, 23, 24, 25, 26, 27]

/// 菜单项闭包载体，避免在 @MainActor 类上暴露 @objc action。
private final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}

/// 状态栏按钮动作载体：区分左键（打开主窗口）与右键（弹出菜单）。
/// 同样用于避免在 @MainActor 类上暴露 @objc action。
private final class StatusBarAction: NSObject {
    private let handler: (NSStatusBarButton?, Bool) -> Void
    init(_ handler: @escaping (NSStatusBarButton?, Bool) -> Void) { self.handler = handler }

    @objc func run(_ sender: Any?) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        handler(sender as? NSStatusBarButton, wantsMenu)
    }
}

/// NSApplication.delegate 是弱/assign 引用，必须显式强持有，
/// 否则 -O 构建下局部变量可能在最后一次使用后释放，状态项随之消失。
@MainActor
private enum DelegateHolder {
    static var instance: AppDelegate?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var statusBarAction: StatusBarAction?
    private var visibilityCancellable: AnyCancellable?
    private var window: NSWindow!
    private var menuActions: [MenuAction] = []
    private let state = AppState()
    // 键盘清洁：基于 CGEvent 的系统级键盘拦截（需「辅助功能」授权）。
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cleanerCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        dwStatusLog("启动参数 \(CommandLine.arguments)")
        dwStatusLog("辅助功能授权=\(AXIsProcessTrusted())")
        // 启动不弹主界面：只驻留菜单栏/后台；窗口在首次需要时懒创建。
        applyStatusItemVisibility()
        // 设置面板里切换「显示菜单栏图标」时立即创建/移除状态项。
        visibilityCancellable = state.settings.$showMenuBarIcon
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyStatusItemVisibility() }
            }
        state.start()
        // 键盘清洁：监听状态开关，自动建立/拆除键盘拦截。
        cleanerCancellable = state.$cleaningMode
            .sink { [weak self] active in
                Task { @MainActor in
                    if active { self?.startCleaning() } else { self?.stopCleaning() }
                }
            }
        // 调试入口：open build/DailyWall.app --args --show-settings
        // 延迟到界面完成首次渲染后再触发 sheet，避免在 didFinishLaunching 里被吞掉。
        if CommandLine.arguments.contains("--show-settings") {
            dwStatusLog("调试参数生效：--show-settings")
            showWindow()
            Task { @MainActor [weak self] in self?.state.showingSettings = true }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
        stopCleaning()
        visibilityCancellable?.cancel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 后台应用：关闭主窗口不退出，可从菜单栏或启动台重新打开。
        false
    }

    /// 从 Dimble 启动器 / 启动台 / 访达再次打开时，直接显示主窗口，
    /// 不需要再从右键菜单里选「打开主窗口」。
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        dwStatusLog("收到重新打开请求（启动器/访达双击）→ 显示主窗口")
        showWindow()
        return true
    }

    // MARK: - 主窗口

    private func buildWindow() {
        dwStatusLog("buildWindow 创建主窗口（懒创建）")
        let hosting = NSHostingController(rootView: ContentView(state: state))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.contentViewController = hosting
        window.title = "DailyWall"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // 只保留「关闭」按钮：去掉最小化（styleMask 不含 .miniaturizable），
        // 并显式隐藏最小化与绿色缩放/全屏两个标准按钮。
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setFrameAutosaveName("DailyWallMainWindow")
        let fitting = hosting.view.fittingSize
        if fitting.height > 200 {
            window.setContentSize(NSSize(width: 430, height: fitting.height))
        }
        window.center()
        window.delegate = self
    }

    private func showWindow() {
        dwStatusLog("showWindow 调出主窗口")
        // 懒创建：启动时不建窗口，首次点图标（Dimble/菜单栏）时才创建。
        if window == nil { buildWindow() }
        state.notifyWindowVisibility(true)
        state.ensurePreviewLoadedIfNeeded()
        positionNearMouse()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 把主窗口定位到鼠标光标附近（菜单栏 app 常见行为：窗口出现在光标下方），
    /// 并约束在光标所在屏幕的可见区域内，避免超出边界被裁切。
    private func positionNearMouse() {
        guard let window = window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = window.frame.size
        let margin: CGFloat = 8

        // 窗口顶边贴在鼠标下方 6pt，水平以鼠标为中心
        var originX = mouse.x - size.width / 2
        var originY = mouse.y - 6 - size.height
        if originX < visible.minX + margin { originX = visible.minX + margin }
        if originX + size.width > visible.maxX - margin { originX = visible.maxX - margin - size.width }
        if originY < visible.minY + margin { originY = visible.minY + margin }
        if originY + size.height > visible.maxY - margin { originY = visible.maxY - margin - size.height }
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    func windowWillClose(_ notification: Notification) {
        state.notifyWindowVisibility(false)
        state.releasePreviewResources()
        // 关窗时若仍在清洁，务必解除键盘拦截，否则只剩鼠标、键盘会卡在禁用状态。
        if state.cleaningMode { state.cleaningMode = false }
        dwStatusLog("主窗口关闭 → 释放预览资源（窗口重开时从磁盘缓存恢复）")
    }

    // MARK: - 键盘清洁

    /// 开启清洁：用 CGEvent 系统级事件拦截吞掉「除鼠标外」的所有事件。
    /// 普通按键是 keyDown(10)/keyUp(11)/flagsChanged(12)；F1–F12 在 macOS 默认作为
    /// 亮度/音量/媒体/调度中心键，走 NX_SYSDEFINED(14) 这类系统定义事件——只订阅键盘
    /// 三类会漏掉它们。因此订阅鼠标事件的补集，任何键盘/功能键事件一律丢弃。
    /// 需要「辅助功能」授权才能创建拦截；鼠标始终可用，点红色按钮即解除。
    private func startCleaning() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            promptAccessibility()
            state.cleaningMode = false
            state.setMessage("全局禁用键盘需要「辅助功能」权限：请到 系统设置 → 隐私与安全性 → 辅助功能，勾选 DailyWall，然后再点一次「清洁键盘」。", isError: true)
            return
        }

        var pointerMask: CGEventMask = 0
        for t in kPointerEventTypes { pointerMask |= CGEventMask(1) << CGEventMask(t) }
        let mask = ~pointerMask

        let callback: CGEventTapCallBack = { _, type, event, _ in
            // 系统超时/被用户输入临时关闭时重新启用，避免键盘悄悄解锁。
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = gCleaningTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            // F1–F12 等功能键以 NX_SYSDEFINED(14) 投递；记录前几次便于确认拦截生效。
            if type.rawValue == 14 && gCleaningSystemEventLogCount < 8 {
                gCleaningSystemEventLogCount += 1
                dwStatusLog("键盘清洁：已拦截功能键/系统控制事件 type=14（第 \(gCleaningSystemEventLogCount) 次）")
            }
            // 返回 nil = 丢弃事件：键盘与功能键不进入任何应用或系统功能。
            return nil
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: nil) else {
            state.cleaningMode = false
            state.setMessage("键盘拦截创建失败：请在「辅助功能」中授权 DailyWall，退出重开应用后再试。", isError: true)
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        gCleaningTap = tap
        gCleaningSystemEventLogCount = 0

        // 让主窗口浮在最上层，保证鼠标随时能点到「结束清洁」按钮。
        window?.level = .floating
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        dwStatusLog("键盘清洁：全局拦截已开启（含 F1–F12 系统控制键，鼠标放行）")
    }

    /// 关闭清洁：停用并销毁拦截，键盘恢复正常。
    private func stopCleaning() {
        guard let tap = eventTap else {
            window?.level = .normal
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        eventTap = nil
        runLoopSource = nil
        gCleaningTap = nil
        window?.level = .normal
        dwStatusLog("键盘清洁：键盘拦截已关闭")
    }

    /// 申请辅助功能权限（系统弹窗 + 打开设置面板的辅助功能页）。
    private func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 菜单栏

    /// 按设置创建或彻底移除状态项。关闭时用 removeStatusItem，
    /// 让系统与 Dimble 不再看到本应用自己的菜单栏图标。
    private func applyStatusItemVisibility() {
        if state.settings.showMenuBarIcon {
            if statusItem == nil { buildStatusItem() }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
                statusMenu = nil
                statusBarAction = nil
                menuActions.removeAll()
            }
            dwStatusLog("状态项未创建（显示菜单栏图标=关）")
        }
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else {
            dwStatusLog("状态项创建失败：button 为 nil")
            return
        }
        button.image = makeMenuBarIcon()
        button.imagePosition = .imageOnly
        button.toolTip = "DailyWall · 左键打开主窗口，右键打开菜单"

        let menu = NSMenu()
        menu.delegate = self
        add(menu, "打开主窗口") { [weak self] in self?.showWindow() }
        menu.addItem(.separator())

        let info = NSMenuItem(title: "今日：获取中…", action: nil, keyEquivalent: "")
        info.isEnabled = false
        info.tag = 99
        menu.addItem(info)
        menu.addItem(.separator())

        add(menu, "立即下载") { [weak self] in
            Task { @MainActor in await self?.state.downloadWithConflictCheck() }
        }
        add(menu, "立即设置桌面") { [weak self] in
            Task { @MainActor in await self?.state.applyDesktop() }
        }
        menu.addItem(.separator())
        add(menu, "设置…") { [weak self] in
            self?.showWindow()
            self?.state.showingSettings = true
        }
        menu.addItem(.separator())
        add(menu, "退出 DailyWall") { NSApp.terminate(nil) }

        // 不设置 statusItem.menu，由按钮 action 区分左右键。
        let action = StatusBarAction { [weak self] target, wantsMenu in
            guard let self else { return }
            if wantsMenu, let target {
                dwStatusLog("右键 → 弹出菜单")
                _ = self.statusMenu?.popUp(positioning: nil,
                                           at: NSPoint(x: 0, y: target.bounds.height + 4),
                                           in: target)
            } else {
                dwStatusLog("左键 → 显示主窗口")
                self.showWindow()
            }
        }

        statusItem = item
        statusMenu = menu
        statusBarAction = action
        button.target = action
        button.action = #selector(StatusBarAction.run(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        dwStatusLog("状态项已创建 左键=主窗口 右键=菜单 window=\(button.window == nil ? "nil" : "OK")")
    }

    /// 菜单栏专用单色模板图：相框 + 日轮 + 山脊，与 App 图标同一视觉语言。
    /// isTemplate = true 让系统按明暗模式自动着色。
    private func makeMenuBarIcon() -> NSImage {
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.set()
            let box = NSInsetRect(rect, 2, 3)
            let frame = NSBezierPath(roundedRect: box, xRadius: 2.5, yRadius: 2.5)
            frame.lineWidth = 1.3
            frame.stroke()

            NSBezierPath(ovalIn: NSRect(x: box.minX + 2.6, y: box.maxY - 5.4,
                                        width: 2.6, height: 2.6)).fill()

            let ridge = NSBezierPath()
            ridge.move(to: NSPoint(x: box.minX + 1.2, y: box.minY + 2.4))
            ridge.line(to: NSPoint(x: box.minX + 4.4, y: box.minY + 5.0))
            ridge.line(to: NSPoint(x: box.minX + 7.4, y: box.minY + 2.7))
            ridge.line(to: NSPoint(x: box.maxX - 1.2, y: box.minY + 4.6))
            ridge.lineWidth = 1.1
            ridge.stroke()
            return true
        }
        icon.isTemplate = true
        return icon
    }

    private func add(_ menu: NSMenu, _ title: String, handler: @escaping () -> Void) {
        let action = MenuAction(handler)
        menuActions.append(action)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        item.target = action
        menu.addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.tag == 99 }) else { return }
        item.title = "今日：" + (state.wallpaper?.title ?? "获取中…")
    }
}

// main.swift 的顶层代码不在 MainActor 隔离上下文；AppDelegate 是 @MainActor，
// 因此启动链必须在 MainActor 上同步建立。
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let appDelegate = AppDelegate()
    DelegateHolder.instance = appDelegate
    application.delegate = appDelegate
    application.setActivationPolicy(.accessory)
    application.run()
}
