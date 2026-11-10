import AppKit
import Foundation

/// 状态项三态对照探针：文字基准 / SF Symbol 原样 / 自绘模板图。
@MainActor
private enum ProbeHolder { static var delegate: ProbeDelegate? }

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var items: [NSStatusItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let itemA = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        itemA.button?.title = "TEST"
        items.append(itemA)

        let itemB = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        itemB.button?.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        itemB.button?.toolTip = "SF Symbol 原样"
        items.append(itemB)

        let itemC = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.set()
            let box = NSInsetRect(rect, 2, 3)
            let frame = NSBezierPath(roundedRect: box, xRadius: 2.5, yRadius: 2.5)
            frame.lineWidth = 1.3
            frame.stroke()
            NSBezierPath(ovalIn: NSRect(x: box.minX + 3, y: box.maxY - 6,
                                        width: 3, height: 3)).fill()
            return true
        }
        icon.isTemplate = true
        itemC.button?.image = icon
        itemC.button?.toolTip = "自绘模板图"
        items.append(itemC)

        try? "statusItems=\(items.count)\n".write(toFile: "/tmp/dw_probe_status.log",
                                                  atomically: true, encoding: .utf8)
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = ProbeDelegate()
    ProbeHolder.delegate = delegate
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
