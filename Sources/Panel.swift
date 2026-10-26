import AppKit

/// 只在子视图明确接管时才接收鼠标，其余区域点击穿透到下层窗口
final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        for sub in subviews.reversed() {
            if let hit = sub.hitTest(point) { return hit }
        }
        return nil
    }
}

final class ClotheslinePanel: NSPanel {

    let lineView: LineView
    private(set) var revealed = false
    /// 彻底收起：绳子与衣架全部消失，只留顶端一个入口
    private(set) var stowed = false
    private var dimmed = false

    private var currentHeight: CGFloat {
        stowed ? Layout.stowHeight : (revealed ? Layout.panelHeight : Layout.ropeZoneHeight)
    }

    /// 展开态顶边（屏幕坐标，y 向上）—— 收起/展开都以此为锚，视觉上从屏幕顶端往下拉
    private var anchorTop: CGFloat { Self.hostScreen().visibleFrame.maxY }

    init(view: LineView) {
        lineView = view
        let screen = Self.hostScreen()
        let width = screen.visibleFrame.width
        super.init(contentRect: NSRect(x: screen.visibleFrame.minX,
                                       y: screen.visibleFrame.maxY - Layout.ropeZoneHeight,
                                       width: width, height: Layout.ropeZoneHeight),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true   // 由鼠标轮询按需接管
        worksWhenModal = true
        animationBehavior = .none
        acceptsMouseMovedEvents = true

        let container = PassThroughView(frame: NSRect(x: 0, y: 0, width: width, height: Layout.panelHeight))
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        contentView = container
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("晾衣架")
    }

    static func hostScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? (NSScreen.main ?? NSScreen.screens[0])
    }

    func reposition() {
        let screen = Self.hostScreen()
        let height = currentHeight
        setFrame(NSRect(x: screen.visibleFrame.minX,
                        y: screen.visibleFrame.maxY - height,
                        width: screen.visibleFrame.width, height: height), display: true)
        lineView.needsDisplay = true
    }

    /// 鼠标悬停展开 / 离开收起：只改变高度，顶边不动，内容像窗帘一样被拉出来
    func setRevealed(_ on: Bool) {
        guard !stowed, on != revealed else { return }
        revealed = on
        applyHeight()
    }

    /// 彻底收起 / 放出来
    func setStowed(_ on: Bool) {
        guard on != stowed else { return }
        stowed = on
        if on { revealed = false }
        lineView.isStowed = on
        applyHeight()
    }

    private func applyHeight() {
        let screen = Self.hostScreen()
        let height = currentHeight
        setFrame(NSRect(x: screen.visibleFrame.minX,
                        y: screen.visibleFrame.maxY - height,
                        width: screen.visibleFrame.width, height: height),
                 display: true, animate: true)
        lineView.needsDisplay = true
    }

    /// 把全局鼠标点换算成展开态布局里的视图坐标（顶边做锚）。
    /// 收起态只承认「入口」那一小条，其余位置一律当作不在栏内。
    func layoutPoint(for screen: NSPoint) -> NSPoint? {
        let dy = anchorTop - screen.y
        guard dy >= 0, dy < (stowed ? Layout.stowHeight : Layout.panelHeight) else { return nil }
        let x = screen.x - frame.minX
        guard x >= 0, x < frame.width else { return nil }
        return NSPoint(x: x, y: dy)
    }

    func setDimmed(_ on: Bool, animated: Bool = true) {
        guard on != dimmed else { return }
        dimmed = on
        let alpha: CGFloat = on ? 0.42 : 1.0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.allowsImplicitAnimation = true
                animator().alphaValue = alpha
            }
        } else {
            alphaValue = alpha
        }
    }
}
