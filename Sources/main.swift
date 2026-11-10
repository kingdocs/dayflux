import AppKit
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var statusBarAction: StatusBarAction?
    private var visibilityCancellable: AnyCancellable?
    private var window: NSWindow!
    private var menuActions: [MenuAction] = []
    private let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        dwStatusLog("启动参数 \(CommandLine.arguments)")
        buildWindow()
        applyStatusItemVisibility()
        // 设置面板里切换「显示菜单栏图标」时立即创建/移除状态项。
        visibilityCancellable = state.settings.$showMenuBarIcon
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyStatusItemVisibility() }
            }
        showWindow()
        state.start()
        // 调试入口：open build/DailyWall.app --args --show-settings
        // 延迟到界面完成首次渲染后再触发 sheet，避免在 didFinishLaunching 里被吞掉。
        if CommandLine.arguments.contains("--show-settings") {
            dwStatusLog("调试参数生效：--show-settings")
            Task { @MainActor [weak self] in self?.state.showingSettings = true }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
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
        let hosting = NSHostingController(rootView: ContentView(state: state))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.contentViewController = hosting
        window.title = "DailyWall"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DailyWallMainWindow")
        let fitting = hosting.view.fittingSize
        if fitting.height > 200 {
            window.setContentSize(NSSize(width: 430, height: fitting.height))
        }
        window.center()
    }

    private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
