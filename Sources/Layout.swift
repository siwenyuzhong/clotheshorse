import AppKit

/// 统一的尺寸与配色（点坐标，视图为 flipped，y 自上而下增大）
enum Layout {
    /// 展开态高度：绳子 + 衣架 + 卡片 + 名称
    static let panelHeight: CGFloat = 138
    /// 收起态高度：只露出绳子；这一段永远对鼠标穿透，
    /// 正好覆盖其他窗口的标题栏与红绿灯
    static let ropeZoneHeight: CGFloat = 46
    static let ropeY: CGFloat = 16
    static let pitch: CGFloat = 84
    static let leftInset: CGFloat = 60
    static let rightInset: CGFloat = 20
    static let hangerHalf: CGFloat = 34
    static let hangerBaseY: CGFloat = 50
    static let cardW: CGFloat = 66
    static let cardH: CGFloat = 54
    static let cardTopY: CGFloat = 52
    static let labelY: CGFloat = 110
    static let addButtonReserve: CGFloat = 58
    static let addButtonRadius: CGFloat = 13
    /// 滚轮平移的灵敏度
    static let scrollGain: CGFloat = 22

    /// 彻底隐藏时的高度：只留屏幕顶端中间一个「绳结」入口
    static let stowHeight: CGFloat = 12
    static let stowHandleW: CGFloat = 54
    static let stowHandleH: CGFloat = 8
}

enum Palette {
    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    static let rope = rgb(240, 236, 228, 0.9)
    static let ropeShade = rgb(0, 0, 0, 0.55)

    static let hangerLight = rgb(226, 230, 237)
    static let hangerDark = rgb(96, 104, 116)

    static let cardBG = rgb(24, 26, 31, 0.92)
    static let cardBorder = rgb(255, 255, 255, 0.14)
    static let cardBorderHover = rgb(255, 255, 255, 0.60)

    /// 亮桌面上白字会消失，所以名称底下垫一小块深色
    static let labelPill = rgb(18, 20, 25, 0.72)
    static let label = rgb(240, 242, 246, 0.96)
    static let labelDim = rgb(214, 218, 226, 0.8)

    static let peg = rgb(200, 154, 98)
    static let pegDark = rgb(150, 108, 62)
    static let accent = rgb(232, 184, 122)

    static let scrim = rgb(8, 9, 12, 0.55)
}
