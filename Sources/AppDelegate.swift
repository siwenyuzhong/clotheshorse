import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, LineViewDelegate {

    private var panel: ClotheslinePanel!
    private var lineView: LineView!
    private var statusItem: NSStatusItem?
    private var dimTimer: Timer?
    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    private let debugLog = ProcessInfo.processInfo.environment["CLOTHESLINE_DEBUG"] != nil
    private let defaults = UserDefaults.standard
    private enum Key {
        static let dimIdle = "dimWhenIdle"
        static let hidden = "hiddenByUser"
        static let hinted = "didShowHint"
    }

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [Key.dimIdle: true, Key.hidden: false])

        lineView = LineView(frame: NSRect(x: 0, y: 0, width: 1440, height: Layout.panelHeight))
        lineView.delegate = self
        panel = ClotheslinePanel(view: lineView)
        panel.orderFrontRegardless()
        if defaults.bool(forKey: Key.hidden) { stowPanel() } else { showPanel() }

        installStatusItem()
        installHotKeys()
        observeScreens()
        startMousePolling()

        if !defaults.bool(forKey: Key.hinted) {
            defaults.set(true, forKey: Key.hinted)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.showWelcome() }
        }
    }

    private func installHotKeys() {
        let hk = HotKeys.shared
        hk.onRegionCapture = { [weak self] in self?.CaptureRegion() }
        hk.onToggleVisibility = { [weak self] in self?.toggleVisibility() }
        hk.onClipboardStash = { [weak self] in self?.stashClipboard() }
        hk.install()
    }

    private func CaptureRegion() { Capture.region(into: lineView) }

    /// 轮询鼠标位置（无需辅助功能权限）：
    /// 1. 指针进入屏幕顶端的绳子那一条 → 整条晾衣架往下拉开；离开 → 收起
    /// 2. 不在衣架上就让面板对鼠标透明，下方窗口的红绿灯、标题栏照常可点
    private func startMousePolling() {
        let timer = Timer(timeInterval: 1.0 / 40.0, repeats: true) { [weak self] _ in
            self?.pollMouse()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        pollMouse()
    }

    private func pollMouse() {
        guard panel.isVisible else { return }
        let screenPoint = NSEvent.mouseLocation
        let buttonDown = (NSEvent.pressedMouseButtons & 1) != 0
        lineView.pointerDown = buttonDown

        let local = panel.layoutPoint(for: screenPoint)
        updateReveal(local, buttonDown: buttonDown)
        // 收起时只有绳子那一段算「在栏内」，别让看不见的卡片抢 hover
        let hoverPoint = local.flatMap { panel.revealed || $0.y < Layout.ropeZoneHeight ? $0 : nil }
        lineView.updatePointer(hoverPoint)

        // 按住鼠标（例如正从别处拖文件过来）时保持可交互，避免拖到一半失去目标
        let shouldReceive = buttonDown || lineView.wantsMouseEvents
        if panel.ignoresMouseEvents == shouldReceive {
            panel.ignoresMouseEvents = !shouldReceive
            if debugLog {
                let lp = hoverPoint ?? NSPoint(x: -1, y: -1)
                NSLog("clothesline: 屏幕(\(Int(screenPoint.x)),\(Int(screenPoint.y))) 视图(\(Int(lp.x)),\(Int(lp.y))) 展开=\(panel.revealed) 接收鼠标=\(shouldReceive)")
            }
        }
    }

    private var keepOpen: Bool {
        lineView.dragInProgress || lineView.menuIsTracking || PreviewController.shared.isShown
    }

    private func updateReveal(_ local: NSPoint?, buttonDown: Bool) {
        if panel.stowed { return }
        guard let p = local else {
            if !keepOpen { panel.setRevealed(false) }
            return
        }
        if panel.revealed { return }
        if p.y < Layout.ropeZoneHeight || buttonDown || lineView.occupiesItem(at: p) {
            panel.setRevealed(true)
        }
    }

    private func observeScreens() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.panel.reposition()
            self?.refreshInterface()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.panel.reposition()
        })
    }

    // MARK: - 状态栏

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusIcon()
        item.button?.toolTip = "晾衣架：把文件挂到屏幕顶端，随时拖进任何应用"
        item.menu = buildMenu()
        statusItem = item
    }

    static func statusIcon() -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 1, y: 14))
            line.line(to: NSPoint(x: rect.maxX - 1, y: 14))
            line.lineWidth = 1.4
            NSColor.black.setStroke()
            line.stroke()

            for cx in [6.0, 14.0] {
                let h = NSBezierPath()
                h.move(to: NSPoint(x: cx, y: 13))
                h.line(to: NSPoint(x: cx - 4, y: 7))
                h.move(to: NSPoint(x: cx, y: 13))
                h.line(to: NSPoint(x: cx + 4, y: 7))
                h.move(to: NSPoint(x: cx - 4, y: 7))
                h.line(to: NSPoint(x: cx + 4, y: 7))
                h.lineWidth = 1.2
                NSColor.black.setStroke()
                h.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        @discardableResult
        func add(_ title: String, _ sel: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let mi = menu.addItem(withTitle: title, action: sel, keyEquivalent: key)
            mi.keyEquivalentModifierMask = mods
            mi.target = self
            return mi
        }
        add("区域截图并挂上", #selector(captureRegion), "2", [.control, .option])
        add("整屏截图并挂上", #selector(captureScreen))
        add("把剪贴板挂上", #selector(stashClipboard), "v", [.control, .option])
        menu.addItem(.separator())
        add("添加文件…", #selector(addFiles), "o")
        add("全部取下", #selector(takeAllDown))
        menu.addItem(.separator())
        let stowed = defaults.bool(forKey: Key.hidden)
        let toggle = add(stowed ? "显示晾衣架" : "隐藏晾衣架", #selector(toggleVisibility), "h", [.control, .option])
        toggle.state = stowed ? .on : .off
        let dim = add("闲置时淡化", #selector(toggleDim))
        dim.state = defaults.bool(forKey: Key.dimIdle) ? .on : .off
        let login = add("开机自启", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add("使用帮助", #selector(showWelcome))
        let quit = add("退出晾衣架", #selector(NSApplication.terminate(_:)), "q")
        // add() 把 target 统一设成了 self，而 terminate: 是 NSApplication 的方法，
        // 必须显式改回来，否则点击会被静默吞掉
        quit.target = NSApp
        return menu
    }

    private func refreshMenu() {
        statusItem?.menu = buildMenu()
    }

    // MARK: - 动作

    @objc func refreshInterface(_ sender: Any? = nil) {
        lineView.needsDisplay = true
        refreshMenu()
    }

    @objc private func captureRegion() { Capture.region(into: lineView) }
    @objc private func captureScreen() { Capture.fullScreen(into: lineView) }
    @objc private func stashClipboard() { ClipboardStash.run(view: lineView) }

    @objc func addFiles() {
        let open = NSOpenPanel()
        open.canChooseFiles = true
        open.canChooseDirectories = true
        open.allowsMultipleSelection = true
        open.prompt = "挂上"
        NSApp.activate(ignoringOtherApps: true)
        if open.runModal() == .OK {
            _ = Store.shared.stash(urls: open.urls)
            refreshInterface()
        }
    }

    @objc private func takeAllDown() {
        guard !Store.shared.items.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "取下全部 \(Store.shared.items.count) 个衣架？"
        alert.informativeText = "复制进晾衣架的文件会被删除；超大文件只移除了引用，原件不受影响。"
        alert.addButton(withTitle: "全部取下")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            Store.shared.removeAll()
            refreshInterface()
        }
    }

    @objc private func toggleVisibility() {
        if defaults.bool(forKey: Key.hidden) { showPanel() } else { stowPanel() }
        refreshMenu()
    }

    private func showPanel() {
        defaults.set(false, forKey: Key.hidden)
        panel.setStowed(false)
        panel.reposition()
        panel.orderFrontRegardless()
        panel.setDimmed(false, animated: false)
        lineView.needsDisplay = true
    }

    /// 绳子、衣架、卡片全部收走，只在屏幕顶端留一个入口
    private func stowPanel() {
        defaults.set(true, forKey: Key.hidden)
        dimTimer?.invalidate()
        dimTimer = nil
        PreviewController.shared.close()
        panel.setRevealed(false)
        panel.setStowed(true)
        panel.orderFrontRegardless()
        panel.setDimmed(false, animated: false)
        refreshInterface()
    }

    func lineViewRequestUnstow() { showPanel() }

    @objc private func toggleDim() {
        defaults.set(!defaults.bool(forKey: Key.dimIdle), forKey: Key.dimIdle)
        refreshMenu()
    }

    @objc private func toggleLogin() {
        let enabled = SMAppService.mainApp.status == .enabled
        do {
            if enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改开机自启"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshMenu()
    }

    @objc func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "屏幕顶上的晾衣架"
        alert.informativeText = """
        · 平时只留一条绳子；鼠标移到绳子上就整体下拉展开，离开自动收起
        · 把文件、截图、文字拖到绳子上就会挂上；一次拖多个文件/文件夹会合并成一个衣架
        · 按住衣架往下拖，拖进文档、聊天窗口、邮件里的就是那个文件本身（成组挂回的会整批还原成文件）
        · 点衣架看大图；右键可打开、重命名、取下
        · 衣架排满一屏后，在栏上滚动鼠标 / 触控板左右滑动就能看后面的
        · 右端 ⊕ 菜单：添加文件 / 区域截图 / 整屏截图 / 挂上剪贴板
        · 绳子和空白处对鼠标穿透，别的窗口的红绿灯照常能点；从别处拖文件过来时才会接管
        · 想彻底收起来：⌃⌥H（或菜单栏图标 → 隐藏晾衣架），绳子衣架全部消失，
          只在屏幕顶端正中间留一个小入口，点它就重新放下来
        · 全局快捷键：⌃⌥2 截图挂上，⌃⌥V 剪贴板挂上，⌃⌥H 收起/放出
        · 首次截图时 macOS 会询问「屏幕录制」权限，允许后即可使用
        """
        alert.addButton(withTitle: "开始使用")
        alert.runModal()
    }

    // MARK: - LineViewDelegate

    func lineViewHover(_ active: Bool) {
        dimTimer?.invalidate()
        dimTimer = nil
        if active {
            panel.setDimmed(false)
        } else if defaults.bool(forKey: Key.dimIdle), !panel.stowed {
            dimTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
                // 定时器可能在收起那一刻还在排队，触发时要再看一眼状态
                guard let self, !self.panel.stowed else { return }
                self.panel.setDimmed(true)
            }
        }
    }

    func lineViewRequestAddFile() { addFiles() }
    func lineViewRequestCapture() { Capture.region(into: lineView) }
}
