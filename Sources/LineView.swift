import AppKit
import UniformTypeIdentifiers

protocol LineViewDelegate: AnyObject {
    func lineViewHover(_ active: Bool)
    func lineViewRequestAddFile()
    func lineViewRequestCapture()
    func lineViewRequestUnstow()
}

final class LineView: NSView, NSDraggingSource {

    weak var delegate: LineViewDelegate?

    private var hoverIndex: Int?
    private var hoverAdd = false
    private var hoverStow = false
    private var dropIndex: Int?
    private var dragIndex: Int?

    /// 鼠标是否按住（轮询写入）。从别处拖文件过来时也是按住状态，
    /// 于是绳子那一段只在「正拖着东西」这一刻接收事件，平时照常穿透
    var pointerDown = false
    /// 正在弹菜单或预览浮层，此时不要收起
    var menuIsTracking = false
    var dragInProgress = false
    /// 彻底收起：只画屏幕顶端那一个入口
    var isStowed = false

    private var lastPointer: NSPoint?
    private var pointerInside = false
    private var scrollOffset: CGFloat = 0

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png,
                                 NSPasteboard.PasteboardType(UTType.image.identifier),
                                 NSPasteboard.PasteboardType(UTType.utf8PlainText.identifier),
                                 .hangerSlot])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 布局

    private var itemCount: Int { Store.shared.items.count }

    private var contentWidth: CGFloat { Layout.leftInset + Layout.pitch * CGFloat(itemCount) }

    /// 右端给 ⊕ 留出安全区，这样最后一个衣架也能完整滑出来
    private var rightGuard: CGFloat { Layout.rightInset + Layout.addButtonReserve }

    private var maxScroll: CGFloat { max(0, contentWidth - (bounds.width - rightGuard)) }

    private func setScroll(_ value: CGFloat) {
        let clamped = min(max(0, value), maxScroll)
        if abs(clamped - scrollOffset) > 0.01 {
            scrollOffset = clamped
            needsDisplay = true
        }
    }

    private func centerX(for slot: Int) -> CGFloat {
        Layout.leftInset + Layout.pitch * (CGFloat(slot) + 0.5) - scrollOffset
    }

    private func cardRect(slot: Int) -> NSRect {
        NSRect(x: centerX(for: slot) - Layout.cardW / 2, y: Layout.cardTopY,
               width: Layout.cardW, height: Layout.cardH)
    }

    private func addButtonCenter() -> NSPoint {
        NSPoint(x: bounds.width - Layout.rightInset - 14, y: Layout.ropeY + 6)
    }

    /// 彻底收起时留在屏幕顶端的那个小入口（留出外扩的点击边距）
    private func stowHandle(expand: CGFloat = 0) -> NSRect {
        NSRect(x: bounds.width / 2 - Layout.stowHandleW / 2 - expand,
               y: -expand,
               width: Layout.stowHandleW + expand * 2,
               height: Layout.stowHandleH + expand).integral
    }

    private var isExpanded: Bool { bounds.height > Layout.ropeZoneHeight + 1 }

    /// 点落在哪个衣架上
    private func slotAt(_ p: NSPoint) -> Int? {
        guard p.y > Layout.ropeZoneHeight - 10 else { return nil }
        let raw = (p.x + scrollOffset - Layout.leftInset) / Layout.pitch
        guard raw >= 0 else { return nil }
        let idx = Int(floor(raw))
        guard idx < itemCount else { return nil }
        return abs(p.x - centerX(for: idx)) <= Layout.pitch / 2 ? idx : nil
    }

    /// 收起态下指针落在衣架列或 ⊕ 上时，也值得把整条拉下来
    func occupiesItem(at p: NSPoint) -> Bool {
        let c = addButtonCenter()
        if hypot(p.x - c.x, p.y - (c.y + 8)) < Layout.addButtonRadius + 8 { return true }
        return slotAt(p) != nil
    }

    /// 把视图上的点映射为「应插入到第几个衣架」
    private func insertionIndex(at p: NSPoint) -> Int {
        guard itemCount > 0 else { return 0 }
        let raw = (p.x + scrollOffset - Layout.leftInset) / Layout.pitch
        if raw < -0.5 { return 0 }
        return min(itemCount, Int(floor(raw + 0.5)))
    }

    /// 只有这些点才接收鼠标，其余位置整条栏对鼠标完全透明
    private func isInteractive(_ p: NSPoint) -> Bool {
        if isStowed { return stowHandle(expand: 6).contains(p) }
        let c = addButtonCenter()
        if hypot(p.x - c.x, p.y - (c.y + 8)) < Layout.addButtonRadius + 8 { return true }
        if p.y < Layout.ropeZoneHeight { return pointerDown }
        // 展开出来的卡片带：内容多到需要左右滑时整条接管；
        // 否则只在指针真正落在某个衣架列上时接管，空白处继续穿透到下面的窗口
        if maxScroll > 0 { return true }
        return slotAt(p) != nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        return isInteractive(local) ? self : nil
    }

    // MARK: - 鼠标轮询（驱动 hover 与穿透）

    func updatePointer(_ local: NSPoint?) {
        lastPointer = local
        let inside = local != nil
        if inside != pointerInside {
            pointerInside = inside
            delegate?.lineViewHover(inside)
        }
        let p = local ?? NSPoint(x: -9999, y: -9999)
        if isStowed {
            let onHandle = stowHandle(expand: 6).contains(p)
            if onHandle != hoverStow {
                hoverStow = onHandle
                needsDisplay = true
            }
            return
        }
        let c = addButtonCenter()
        let near = hypot(p.x - c.x, p.y - (c.y + 8)) < Layout.addButtonRadius + 8
        let slot = (near || p.y < Layout.ropeZoneHeight) ? nil : slotAt(p)
        if slot != hoverIndex || near != hoverAdd {
            hoverIndex = slot; hoverAdd = near
            needsDisplay = true
        }
    }

    /// 面板此刻是否应该接收鼠标事件
    var wantsMouseEvents: Bool {
        if dragInProgress || menuIsTracking { return true }
        guard let p = lastPointer else { return false }
        return isInteractive(p)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        if isStowed {
            drawStowHandle()
            return
        }
        drawRope()
        let expanded = isExpanded

        if expanded, let di = dropIndex {
            let x = Layout.leftInset + Layout.pitch * CGFloat(di) - scrollOffset
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: Layout.ropeY - 10))
            line.line(to: NSPoint(x: x, y: Layout.panelHeight - 8))
            Palette.accent.setStroke()
            line.lineWidth = 2
            line.stroke()
        }

        if !expanded {
            // 收起态绳上空无一物：衣架连同卡片一起藏回顶缘外，指针探进来才把整条拉下来
            drawAddButton()
            return
        }
        for i in 0..<itemCount {
            let cx = centerX(for: i)
            if cx < -Layout.pitch / 2 || cx > bounds.width + Layout.pitch / 2 { continue }
            let item = Store.shared.items[i]
            drawHanger(cx: cx, hovered: hoverIndex == i, dimmed: dragIndex == i)
            drawCard(item: item, rect: cardRect(slot: i), hovered: hoverIndex == i,
                     dimmed: dragIndex == i)
        }
        drawScrollIndicator()
        drawAddButton()
    }

    private func drawRope() {
        let y = Layout.ropeY
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -6, y: y))
        var x: CGFloat = -6
        while x < bounds.width {
            let next = min(x + 240, bounds.width + 6)
            let mid = (x + next) / 2
            path.curve(to: NSPoint(x: next, y: y + 1),
                       controlPoint1: NSPoint(x: mid - 50, y: y + 5.5),
                       controlPoint2: NSPoint(x: mid + 50, y: y + 5.5))
            x = next
        }
        Palette.ropeShade.setStroke()
        path.lineWidth = 3.4
        path.stroke()
        Palette.rope.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawHanger(cx: CGFloat, hovered: Bool, dimmed: Bool) {
        let alpha: CGFloat = dimmed ? 0.25 : (hovered ? 1 : 0.85)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: hovered ? -2 : 0)
        transform.concat()

        let hook = NSBezierPath()
        hook.move(to: NSPoint(x: cx, y: Layout.ropeY + 6))
        hook.line(to: NSPoint(x: cx, y: Layout.ropeY - 6))
        hook.curve(to: NSPoint(x: cx + 13, y: Layout.ropeY + 3),
                   controlPoint1: NSPoint(x: cx + 9, y: Layout.ropeY - 7),
                   controlPoint2: NSPoint(x: cx + 14, y: Layout.ropeY - 5))
        strokeHanger(hook, width: 2.4, alpha: alpha)

        let body = NSBezierPath()
        let apex = NSPoint(x: cx, y: Layout.ropeY + 6)
        let left = NSPoint(x: cx - Layout.hangerHalf, y: Layout.hangerBaseY)
        let right = NSPoint(x: cx + Layout.hangerHalf, y: Layout.hangerBaseY)
        body.move(to: apex); body.line(to: left)
        body.move(to: apex); body.line(to: right)
        body.move(to: left); body.line(to: right)
        strokeHanger(body, width: 3, alpha: alpha)

        NSGraphicsContext.restoreGraphicsState()
    }

    private func strokeHanger(_ path: NSBezierPath, width: CGFloat, alpha: CGFloat) {
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.lineWidth = width
        Palette.hangerDark.withAlphaComponent(alpha).setStroke()
        path.stroke()
        path.lineWidth = max(1, width * 0.45)
        Palette.hangerLight.withAlphaComponent(alpha * 0.85).setStroke()
        path.stroke()
    }

    private func drawCard(item: ShelfItem, rect: NSRect, hovered: Bool, dimmed: Bool) {
        let lift: CGFloat = hovered ? -2 : 0
        let r = rect.offsetBy(dx: 0, dy: lift)

        if item.isGroup {
            // 后面叠两张，表示这个衣架上挂着好几件
            let offsets: [CGFloat] = [7, 3.5]
            for (i, off) in offsets.enumerated() {
                let ghost = NSBezierPath(roundedRect: r.offsetBy(dx: off, dy: -off * 0.75),
                                         xRadius: 8, yRadius: 8)
                Palette.rgb(24, 26, 31, dimmed ? 0.2 : (i == 0 ? 0.6 : 0.35)).setFill()
                ghost.fill()
                ghost.lineWidth = 1
                Palette.cardBorder.setStroke()
                ghost.stroke()
            }
        }

        let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        (dimmed ? NSColor.white.withAlphaComponent(0.06) : Palette.cardBG).setFill()
        path.fill()

        if item.kind == .text, let text = item.previewText() {
            drawPaperText(text, in: r)
        } else if let image = item.image() {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let fill = AspectFill(image: image, in: r)
            image.draw(in: fill.rect, from: .zero, operation: .sourceOver,
                       fraction: dimmed ? 0.25 : 1.0, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let icon = item.systemIcon()
            let side: CGFloat = 34
            let box = NSRect(x: r.midX - side / 2, y: r.minY + 4, width: side, height: side)
            icon.draw(in: box, from: .zero, operation: .sourceOver,
                      fraction: dimmed ? 0.3 : 1.0, respectFlipped: true, hints: nil)
            let badge = (item.isGroup ? "\(item.memberCount)件"
                        : (item.extBadge.isEmpty ? "FILE" : item.extBadge)) as NSString
            badge.draw(in: NSRect(x: r.minX, y: r.maxY - 16, width: r.width, height: 13),
                       withAttributes: [.font: NSFont.systemFont(ofSize: 8.5, weight: .bold),
                                         .foregroundColor: Palette.accent,
                                         .paragraphStyle: centeredStyle()])
        }

        let border = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        border.lineWidth = hovered ? 1.4 : 1
        (hovered ? Palette.cardBorderHover : Palette.cardBorder).setStroke()
        border.stroke()

        drawPeg(at: NSPoint(x: r.midX, y: Layout.hangerBaseY + lift), hovered: hovered)
        drawLabel(item.displayName as NSString, atX: r.midX, hovered: hovered)
    }

    private func drawPaperText(_ text: String, in rect: NSRect) {
        let paper = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        Palette.rgb(246, 243, 236, 0.96).setFill()
        paper.fill()
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 0.5
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 6.2, weight: .regular),
            .foregroundColor: Palette.rgb(60, 62, 68, 0.95),
            .paragraphStyle: para
        ]
        let s = text.replacingOccurrences(of: "\n", with: "↩ ") as NSString
        s.draw(in: rect.insetBy(dx: 5, dy: 4), withAttributes: attrs)
    }

    /// 亮桌面上纯白字会看不见，所以名称底下垫一小块深色
    private func drawLabel(_ text: NSString, atX midX: CGFloat, hovered: Bool) {
        let font = NSFont.systemFont(ofSize: 9, weight: .medium)
        let measure: [NSAttributedString.Key: Any] = [.font: font]
        let maxW = Layout.pitch - 10
        let shown = text.size(withAttributes: measure).width > maxW
            ? (text as String).truncated(toWidth: maxW, attrs: measure) : (text as String)
        let pillW = min((shown as NSString).size(withAttributes: measure).width + 11, maxW)
        let box = NSRect(x: midX - pillW / 2, y: Layout.labelY + (hovered ? -2 : 0),
                         width: pillW, height: 15)
        let pill = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        Palette.labelPill.setFill()
        pill.fill()
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingMiddle
        (shown as NSString).draw(in: box, withAttributes: [.font: font,
                                                          .foregroundColor: hovered ? Palette.label : Palette.labelDim,
                                                          .paragraphStyle: para])
    }

    private func drawPeg(at p: NSPoint, hovered: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: p.x, yBy: p.y)
        t.rotate(byDegrees: hovered ? -6 : 5)
        t.concat()
        let peg = NSBezierPath(roundedRect: NSRect(x: -3.2, y: -8, width: 6.4, height: 17), xRadius: 2, yRadius: 2)
        (hovered ? Palette.accent : Palette.peg).setFill()
        peg.fill()
        let gap = NSBezierPath()
        gap.move(to: NSPoint(x: 0, y: -5))
        gap.line(to: NSPoint(x: 0, y: 5))
        Palette.pegDark.setStroke()
        gap.lineWidth = 1
        gap.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawScrollIndicator() {
        guard maxScroll > 0 else { return }
        let trackW: CGFloat = 100
        let box = NSRect(x: bounds.width - rightGuard - trackW - 10, y: Layout.panelHeight - 7,
                         width: trackW, height: 3)
        let track = NSBezierPath(roundedRect: box, xRadius: 1.5, yRadius: 1.5)
        Palette.rgb(255, 255, 255, 0.18).setFill()
        track.fill()

        let ratio = min(1, (bounds.width - rightGuard) / contentWidth)
        let knobW = max(16, trackW * ratio)
        let knobX = box.minX + (trackW - knobW) * (scrollOffset / maxScroll)
        let knob = NSBezierPath(roundedRect: NSRect(x: knobX, y: box.minY, width: knobW, height: box.height),
                               xRadius: 1.5, yRadius: 1.5)
        Palette.accent.setFill()
        knob.fill()
    }

    /// 收起时留在屏幕顶端的小入口：一截绳 + 一个木夹，点它把整条拉回来
    private func drawStowHandle() {
        let r = stowHandle()
        let rope = NSBezierPath()
        rope.move(to: NSPoint(x: r.minX - 26, y: r.midY))
        rope.curve(to: NSPoint(x: r.maxX + 26, y: r.midY),
                   controlPoint1: NSPoint(x: r.midX - 26, y: r.midY + 4),
                   controlPoint2: NSPoint(x: r.midX + 26, y: r.midY + 4))
        Palette.ropeShade.setStroke()
        rope.lineWidth = 3
        rope.stroke()
        Palette.rope.setStroke()
        rope.lineWidth = 1.4
        rope.stroke()

        let pill = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        (hoverStow ? Palette.accent : Palette.cardBG).setFill()
        pill.fill()
        pill.lineWidth = 1.2
        (hoverStow ? Palette.accent : Palette.cardBorderHover).setStroke()
        pill.stroke()

        // 中间两个小竖线，暗示「往两边拉开」
        let marks = NSBezierPath()
        for dx: CGFloat in [-5, 5] {
            marks.move(to: NSPoint(x: r.midX + dx, y: r.midY - 2))
            marks.line(to: NSPoint(x: r.midX + dx, y: r.midY + 2))
        }
        marks.lineWidth = 1.4
        marks.lineCapStyle = .round
        (hoverStow ? Palette.rgb(30, 26, 20) : Palette.label).setStroke()
        marks.stroke()
    }

    private func drawAddButton() {
        let c = addButtonCenter()
        let r = Layout.addButtonRadius
        let circle = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r + 8, width: r * 2, height: r * 2))
        (hoverAdd ? Palette.accent : Palette.scrim).setFill()
        circle.fill()
        circle.lineWidth = 1.2
        (hoverAdd ? Palette.accent : Palette.rope).setStroke()
        circle.stroke()

        let cross = NSBezierPath()
        let cy = c.y + 8
        cross.move(to: NSPoint(x: c.x - 6, y: cy)); cross.line(to: NSPoint(x: c.x + 6, y: cy))
        cross.move(to: NSPoint(x: c.x, y: cy - 6)); cross.line(to: NSPoint(x: c.x, y: cy + 6))
        cross.lineWidth = 1.8
        cross.lineCapStyle = .round
        (hoverAdd ? Palette.rgb(30, 26, 20) : Palette.label).setStroke()
        cross.stroke()

        if isExpanded { drawLabel("挂上" as NSString, atX: c.x, hovered: hoverAdd) }
    }

    private func centeredStyle() -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = .byTruncatingTail
        return p
    }

    // MARK: - 事件

    override func scrollWheel(with event: NSEvent) {
        guard maxScroll > 0 else { return }
        var delta = event.scrollingDeltaX
        if abs(delta) < abs(event.scrollingDeltaY) { delta = event.scrollingDeltaY }
        let gain: CGFloat = event.hasPreciseScrollingDeltas ? 1 : Layout.scrollGain
        setScroll(scrollOffset - delta * gain)
    }

    /// 把某个序号滑进当前这一屏
    func revealSlot(_ index: Int) {
        guard maxScroll > 0 else { return }
        setScroll(Layout.leftInset + Layout.pitch * (CGFloat(index) + 0.5) - bounds.width / 2)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let p = convert(event.locationInWindow, from: nil)

        if isStowed {
            if stowHandle(expand: 6).contains(p) { delegate?.lineViewRequestUnstow() }
            return
        }

        let c = addButtonCenter()

        if hypot(p.x - c.x, p.y - (c.y + 8)) < Layout.addButtonRadius + 6 {
            withTracking { showAddMenu(at: NSPoint(x: c.x - 40, y: c.y + 18)) }
            return
        }
        guard let slot = slotAt(p), Store.shared.items.indices.contains(slot) else { return }
        let item = Store.shared.items[slot]

        // 区分点击（预览）与拖拽（取下来丢到别处）
        let start = event.locationInWindow
        var dragEvent: NSEvent?
        let deadline = Date().addingTimeInterval(0.45)
        while Date() < deadline {
            // 必须用带 untilDate 的版本：不带的那个不阻塞，拖拽事件常常还没入队就被当成点击
            guard let ev = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                            until: deadline, inMode: .eventTracking, dequeue: true) else { break }
            if ev.type == .leftMouseUp { dragEvent = nil; break }
            let here = ev.locationInWindow
            if hypot(here.x - start.x, here.y - start.y) > 4 { dragEvent = ev; break }
        }

        if let ev = dragEvent {
            startDrag(item: item, slot: slot, event: ev)
        } else {
            let rect = cardRect(slot: slot)
            if NSMouseInRect(p, rect, isFlipped) {
                withTracking { PreviewController.shared.toggle(item: item, anchor: rect, in: window, view: self) }
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let slot = slotAt(p), Store.shared.items.indices.contains(slot) else {
            withTracking { showAddMenu(at: p) }
            return
        }
        let item = Store.shared.items[slot]
        let menu = ContextMenu.menu(for: item, index: slot, view: self)
        withTracking { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }

    /// 菜单/浮层打开期间保持展开、保持接收鼠标
    private func withTracking(_ body: () -> Void) {
        menuIsTracking = true
        body()
        menuIsTracking = false
        needsDisplay = true
    }

    private func showAddMenu(at point: NSPoint) {
        let menu = NSMenu()
        menu.addItem(withTitle: "添加文件…", action: #selector(chooseFiles), keyEquivalent: "").target = self
        menu.addItem(withTitle: "区域截图并挂上", action: #selector(captureRegion), keyEquivalent: "").target = self
        menu.addItem(withTitle: "全屏截图并挂上", action: #selector(captureScreen), keyEquivalent: "").target = self
        menu.addItem(withTitle: "把剪贴板挂上", action: #selector(stashClipboard), keyEquivalent: "").target = self
        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func chooseFiles() { delegate?.lineViewRequestAddFile() }
    @objc private func captureRegion() { delegate?.lineViewRequestCapture() }
    @objc private func captureScreen() { Capture.fullScreen(into: self) }
    @objc private func stashClipboard() { ClipboardStash.run() }

    // MARK: - 拖出

    private func startDrag(item: ShelfItem, slot: Int, event: NSEvent) {
        let writer = ShelfWriter(item: item, slotIndex: slot)
        let rect = cardRect(slot: slot)
        let sessionItems = writer.makeDraggingItems(frame: rect.insetBy(dx: -4, dy: -4),
                                                   contents: item.image() ?? item.systemIcon())
        dragIndex = slot
        dragInProgress = true
        needsDisplay = true
        beginDraggingSession(with: sessionItems, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragIndex = nil
        dropIndex = nil
        dragInProgress = false
        needsDisplay = true
    }

    // MARK: - 拖入

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragInProgress = true
        updateDropIndex(from: sender)
        return acceptedOperation(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragInProgress = true
        updateDropIndex(from: sender)
        return acceptedOperation(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragInProgress = false
        dropIndex = nil
        needsDisplay = true
    }

    private func acceptedOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if pb.availableType(from: [.hangerSlot]) != nil { return .move }
        if pb.availableType(from: [.fileURL]) != nil { return .copy }
        if pb.availableType(from: [.URL]) != nil { return .copy }
        if pb.availableType(from: [.tiff, .png]) != nil { return .copy }
        if pb.availableType(from: [.string]) != nil { return .copy }
        return []
    }

    private func updateDropIndex(from sender: NSDraggingInfo) {
        let p = convert(sender.draggingLocation, from: nil)
        let idx = insertionIndex(at: p)
        if idx != dropIndex { dropIndex = idx; needsDisplay = true }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropIndex = nil
        dragInProgress = false
        let pb = sender.draggingPasteboard
        let target = insertionIndex(at: convert(sender.draggingLocation, from: nil))

        if let data = pb.data(forType: .hangerSlot),
           let text = String(data: data, encoding: .utf8), let from = Int(text),
           Store.shared.items.indices.contains(from) {
            let id = Store.shared.items[from].id
            let moving = from < target ? target - 1 : target
            dragIndex = nil
            Store.shared.move(id: id, to: moving)
            needsDisplay = true
            Bus.refresh()
            return true
        }

        var placed: ShelfItem?
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            placed = Store.shared.stash(urls: urls, preferredIndex: target)
        }
        if placed == nil,
           let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = images.first, let tiff = first.tiffRepresentation {
            let stamp = DateFormatter.hhmmss.string(from: Date())
            placed = Store.shared.stash(image: tiff, name: "贴图 \(stamp).png", at: target)
        }
        if placed == nil,
           let strings = pb.readObjects(forClasses: [NSString.self], options: nil) as? [String],
           let body = strings.first, !body.isEmpty {
            placed = Store.shared.stash(text: body, name: "", at: target)
        }
        needsDisplay = true
        if let placed {
            revealSlot(Store.shared.index(of: placed.id) ?? 0)
            Bus.refresh()
            return true
        }
        return false
    }
}

/// 图像按比例填满卡片
struct AspectFill {
    let rect: NSRect
    init(image: NSImage, in rect: NSRect) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { self.rect = rect; return }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        self.rect = NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

extension String {
    /// 按像素宽度截断，保证名称底色块不会挤到旁边的衣架
    func truncated(toWidth width: CGFloat, attrs: [NSAttributedString.Key: Any]) -> String {
        var kept = self
        while !kept.isEmpty, (kept + "…").size(withAttributes: attrs).width > width {
            kept.removeLast()
        }
        return kept.isEmpty ? "…" : kept + "…"
    }
}

extension DateFormatter {
    static let hhmmss: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH-mm-ss"
        return f
    }()
}
