import AppKit

/// 生成 AppIcon 各尺寸 PNG：swift Tools/icon/main.swift <输出目录>
/// 坐标系：标准 AppKit（左下原点，y 向上）
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(s)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func draw(_ s: CGFloat) {
    let u = s / 1024
    let rect = NSRect(x: 0, y: 0, width: s, height: s)

    let body = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.045, dy: s * 0.045),
                            xRadius: s * 0.215, yRadius: s * 0.215)
    body.addClip()
    NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.86, blue: 0.71, alpha: 1),
                        NSColor(srgbRed: 0.99, green: 0.66, blue: 0.50, alpha: 1),
                        NSColor(srgbRed: 0.66, green: 0.40, blue: 0.42, alpha: 1)])!
        .draw(in: rect, angle: -90)
    NSGradient(colors: [NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0.0)])!
        .draw(in: rect, angle: -90)

    let ropeTop = s * 0.74
    let ropeColor = NSColor(srgbRed: 0.36, green: 0.24, blue: 0.18, alpha: 0.95)

    let rope = NSBezierPath()
    rope.move(to: NSPoint(x: s * 0.01, y: ropeTop))
    rope.curve(to: NSPoint(x: s * 0.99, y: ropeTop),
               controlPoint1: NSPoint(x: s * 0.34, y: ropeTop - s * 0.075),
               controlPoint2: NSPoint(x: s * 0.66, y: ropeTop - s * 0.075))
    rope.lineWidth = 17 * u
    rope.lineCapStyle = .round
    ropeColor.setStroke()
    rope.stroke()

    let metal = NSColor(srgbRed: 0.99, green: 0.96, blue: 0.93, alpha: 1)
    let metalDim = NSColor(srgbRed: 0.80, green: 0.72, blue: 0.66, alpha: 1)

    func hanger(cx: CGFloat, hangY: CGFloat, halfW: CGFloat, drop: CGFloat) {
        let hook = NSBezierPath()
        hook.move(to: NSPoint(x: cx, y: hangY))
        hook.line(to: NSPoint(x: cx, y: hangY + s * 0.062))
        hook.curve(to: NSPoint(x: cx + s * 0.052, y: hangY + s * 0.020),
                   controlPoint1: NSPoint(x: cx + s * 0.042, y: hangY + s * 0.066),
                   controlPoint2: NSPoint(x: cx + s * 0.058, y: hangY + s * 0.040))
        hook.lineWidth = 13 * u
        hook.lineCapStyle = .round
        metalDim.setStroke()
        hook.stroke()

        let apex = NSPoint(x: cx, y: hangY)
        let left = NSPoint(x: cx - halfW, y: hangY - drop)
        let right = NSPoint(x: cx + halfW, y: hangY - drop)
        let tri = NSBezierPath()
        tri.move(to: apex); tri.line(to: left)
        tri.move(to: apex); tri.line(to: right)
        tri.move(to: left); tri.line(to: right)
        tri.lineWidth = 15 * u
        tri.lineJoinStyle = .round
        tri.lineCapStyle = .round
        metal.setStroke()
        tri.stroke()
    }

    func card(cx: CGFloat, topY: CGFloat, w: CGFloat, h: CGFloat, tint: NSColor, pegAngle: CGFloat) {
        let r = NSRect(x: cx - w / 2, y: topY - h, width: w, height: h)
        let path = NSBezierPath(roundedRect: r, xRadius: s * 0.024, yRadius: s * 0.024)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0.25, alpha: 0.30)
        shadow.shadowBlurRadius = 22 * u
        shadow.shadowOffset = NSSize(width: 0, height: -8 * u)
        shadow.set()
        NSColor(white: 0.99, alpha: 1).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(colors: [tint.withAlphaComponent(0.62), tint.withAlphaComponent(0.14)])?
            .draw(in: r, angle: -55)
        path.lineWidth = 5 * u
        NSColor(white: 0.22, alpha: 0.16).setStroke()
        path.stroke()

        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: cx, yBy: topY)
        t.rotate(byDegrees: pegAngle)
        t.concat()
        let peg = NSBezierPath(roundedRect: NSRect(x: -s * 0.017, y: -s * 0.048,
                                                   width: s * 0.034, height: s * 0.096),
                               xRadius: s * 0.011, yRadius: s * 0.011)
        NSColor(srgbRed: 0.86, green: 0.63, blue: 0.36, alpha: 1).setFill()
        peg.fill()
        let seam = NSBezierPath()
        seam.move(to: NSPoint(x: 0, y: -s * 0.032))
        seam.line(to: NSPoint(x: 0, y: s * 0.032))
        seam.lineWidth = 3.5 * u
        NSColor(srgbRed: 0.52, green: 0.34, blue: 0.19, alpha: 0.85).setStroke()
        seam.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    let hangY = ropeTop - s * 0.030
    let drop = s * 0.095
    let cardTop = hangY - drop
    hanger(cx: s * 0.33, hangY: hangY, halfW: s * 0.125, drop: drop)
    hanger(cx: s * 0.67, hangY: hangY, halfW: s * 0.125, drop: drop)
    card(cx: s * 0.33, topY: cardTop, w: s * 0.245, h: s * 0.215,
         tint: NSColor(srgbRed: 0.34, green: 0.62, blue: 0.92, alpha: 1), pegAngle: -7)
    card(cx: s * 0.67, topY: cardTop, w: s * 0.245, h: s * 0.215,
         tint: NSColor(srgbRed: 0.40, green: 0.76, blue: 0.52, alpha: 1), pegAngle: 6)
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in specs {
    let data = render(CGFloat(size)).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
try! render(1024).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "\(outDir)/master.png"))

// 像素校验：沿 x=33% 自上而下扫描，绳子（深色）必须先于卡片（浅色）出现
let check = render(400)
var firstDark = -1, firstCard = -1
for row in 0..<400 {
    guard let c = check.colorAt(x: 132, y: row), c.alphaComponent > 0.5 else { continue }
    let lum = 0.3 * c.redComponent + 0.59 * c.greenComponent + 0.11 * c.blueComponent
    if firstDark < 0 && lum < 0.32 { firstDark = row }
    if firstCard < 0 && c.blueComponent > 0.88 && c.redComponent < 0.75 { firstCard = row }
}
print("绳子首行 \(firstDark) / 卡片首行 \(firstCard) → " +
      (firstDark > 0 && firstCard > firstDark ? "绳子在上、衣架垂在下 ✓" : "上下关系不对 ✗"))
print("图标已生成于 \(outDir)")
