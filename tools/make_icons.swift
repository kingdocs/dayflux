import AppKit
import CoreGraphics
import Foundation

// DailyWall App 图标：黄昏湖景 + 日轮 + 倒影，纯矢量绘制，输出标准 iconset。
// 用法：cp tools/make_icons.swift /tmp/dw_iconbuild/main.swift
//       swiftc -O -swift-version 5 /tmp/dw_iconbuild/main.swift -o /tmp/make_icons
//       /tmp/make_icons <输出目录>

private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

private func drawIcon(_ ctx: CGContext, _ s: CGFloat) {
    let full = CGRect(x: 0, y: 0, width: s, height: s)
    let radius = s * 0.225
    let shape = CGPath(roundedRect: full, cornerWidth: radius,
                       cornerHeight: radius, transform: nil)
    ctx.addPath(shape)
    ctx.clip()

    let cs = CGColorSpaceCreateDeviceRGB()

    // 天空：深靛蓝 → 紫 → 珊瑚 → 暖金
    let skyStops = [rgb(12, 22, 52), rgb(46, 48, 112), rgb(122, 68, 132),
                    rgb(226, 124, 105), rgb(250, 190, 126), rgb(252, 214, 160)] as CFArray
    let skyLocs: [CGFloat] = [0, 0.28, 0.50, 0.68, 0.82, 1]
    if let sky = CGGradient(colorsSpace: cs, colors: skyStops, locations: skyLocs) {
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: s),
                               end: CGPoint(x: 0, y: 0), options: [])
    }

    let sun = CGPoint(x: s * 0.5, y: s * 0.56)
    let sunR = s * 0.115

    // 日轮光晕
    let glowStops = [rgb(255, 220, 168, 0.46), rgb(255, 220, 168, 0)] as CFArray
    if let glow = CGGradient(colorsSpace: cs, colors: glowStops, locations: [0, 1]) {
        ctx.drawRadialGradient(glow, startCenter: sun, startRadius: sunR * 0.5,
                               endCenter: sun, endRadius: s * 0.36, options: [])
    }

    // 星点
    let stars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0.18, 0.86, 0.006, 0.65), (0.30, 0.91, 0.004, 0.5),
        (0.72, 0.88, 0.005, 0.55), (0.85, 0.79, 0.0035, 0.4)
    ]
    for (x, y, r, a) in stars {
        ctx.setFillColor(rgb(255, 250, 240, a))
        ctx.fillEllipse(in: CGRect(x: (x - r) * s, y: (y - r) * s,
                                   width: r * 2 * s, height: r * 2 * s))
    }

    // 日轮
    ctx.setFillColor(rgb(255, 246, 220))
    ctx.fillEllipse(in: CGRect(x: sun.x - sunR, y: sun.y - sunR,
                               width: sunR * 2, height: sunR * 2))

    // 远山
    ctx.setFillColor(rgb(62, 52, 104, 0.92))
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 0, y: 0.34 * s))
    ctx.addCurve(to: CGPoint(x: 0.30 * s, y: 0.445 * s),
                 control1: CGPoint(x: 0.10 * s, y: 0.405 * s),
                 control2: CGPoint(x: 0.20 * s, y: 0.445 * s))
    ctx.addCurve(to: CGPoint(x: 0.62 * s, y: 0.392 * s),
                 control1: CGPoint(x: 0.42 * s, y: 0.448 * s),
                 control2: CGPoint(x: 0.52 * s, y: 0.390 * s))
    ctx.addCurve(to: CGPoint(x: s, y: 0.43 * s),
                 control1: CGPoint(x: 0.76 * s, y: 0.392 * s),
                 control2: CGPoint(x: 0.88 * s, y: 0.43 * s))
    ctx.addLine(to: CGPoint(x: s, y: 0))
    ctx.addLine(to: CGPoint(x: 0, y: 0))
    ctx.closePath()
    ctx.fillPath()

    // 近山
    ctx.setFillColor(rgb(26, 34, 70))
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 0, y: 0.34 * s))
    ctx.addCurve(to: CGPoint(x: 0.35 * s, y: 0.402 * s),
                 control1: CGPoint(x: 0.12 * s, y: 0.372 * s),
                 control2: CGPoint(x: 0.24 * s, y: 0.402 * s))
    ctx.addCurve(to: CGPoint(x: 0.70 * s, y: 0.356 * s),
                 control1: CGPoint(x: 0.48 * s, y: 0.402 * s),
                 control2: CGPoint(x: 0.58 * s, y: 0.352 * s))
    ctx.addCurve(to: CGPoint(x: s, y: 0.382 * s),
                 control1: CGPoint(x: 0.84 * s, y: 0.360 * s),
                 control2: CGPoint(x: 0.92 * s, y: 0.382 * s))
    ctx.addLine(to: CGPoint(x: s, y: 0))
    ctx.addLine(to: CGPoint(x: 0, y: 0))
    ctx.closePath()
    ctx.fillPath()

    // 水面
    let waterStops = [rgb(34, 50, 92), rgb(12, 20, 44)] as CFArray
    if let wg = CGGradient(colorsSpace: cs, colors: waterStops, locations: [0, 1]) {
        ctx.drawLinearGradient(wg, start: CGPoint(x: 0, y: 0.34 * s),
                               end: CGPoint(x: 0, y: 0), options: [])
    }

    // 日轮倒影
    for i in 0..<6 {
        let y = (0.298 - CGFloat(i) * 0.046) * s
        let w = (0.17 - CGFloat(i) * 0.019) * s
        let h = max(s * 0.007, 1)
        let a = 0.26 - CGFloat(i) * 0.035
        ctx.setFillColor(rgb(255, 226, 178, a))
        let r = CGRect(x: s * 0.5 - w / 2, y: y, width: w, height: h)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: h / 2,
                           cornerHeight: h / 2, transform: nil))
        ctx.fillPath()
    }

    // 顶部柔光
    let sheenStops = [rgb(255, 255, 255, 0.12), rgb(255, 255, 255, 0)] as CFArray
    if let sheen = CGGradient(colorsSpace: cs, colors: sheenStops, locations: [0, 1]) {
        ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: s),
                               end: CGPoint(x: 0, y: 0.55 * s), options: [])
    }

    // 细白内描边
    let inset = s * 0.016
    let inner = CGPath(roundedRect: full.insetBy(dx: inset, dy: inset),
                       cornerWidth: radius - inset, cornerHeight: radius - inset,
                       transform: nil)
    ctx.addPath(inner)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.18))
    ctx.setLineWidth(s * 0.009)
    ctx.strokePath()
}

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output,
                                         withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let gc = NSGraphicsContext(bitmapImageRep: rep) else {
        FileHandle.standardError.write("生成失败: \(name)\n".data(using: .utf8)!)
        continue
    }
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)))
    drawIcon(ctx, CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: output + "/" + name))
        print("\(name) \(px)x\(px)")
    }
}
