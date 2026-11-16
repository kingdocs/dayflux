import AppKit

/// 主窗口定位：固定放在菜单栏所在屏幕的右上角，不跟随鼠标。
/// 计算与 AppKit 界面状态解耦，便于冒烟测试直接断言坐标。
enum WindowPlacement {
    /// 与屏幕右边缘、菜单栏下沿的留白。
    static let edgeMargin: CGFloat = 20

    /// visibleFrame 由系统排除菜单栏与 Dock，直接用它算右上角位置。
    /// 返回值是窗口左下角在全局屏幕坐标系中的原点。
    static func topRightOrigin(visibleFrame: NSRect, windowSize: NSSize) -> NSPoint {
        var x = visibleFrame.maxX - edgeMargin - windowSize.width
        var y = visibleFrame.maxY - edgeMargin - windowSize.height
        // 极小屏幕（窗口比可见区还大）兜底：左上角仍留在可见区内，不被裁出屏幕。
        if x < visibleFrame.minX + edgeMargin { x = visibleFrame.minX + edgeMargin }
        if y < visibleFrame.minY + edgeMargin { y = visibleFrame.minY + edgeMargin }
        return NSPoint(x: x, y: y)
    }
}
