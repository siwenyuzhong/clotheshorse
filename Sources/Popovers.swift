import AppKit

// MARK: - 单件操作

final class ItemActions: NSObject {
    let item: ShelfItem
    private weak var view: NSView?

    init(_ item: ShelfItem, view: NSView?) {
        self.item = item
        self.view = view
    }

    func refresh() {
        view?.needsDisplay = true
        Bus.refresh()
    }

    @objc func open() {
        let targets = item.liveMemberURLs
        guard !targets.isEmpty else { NSSound.beep(); note("文件已不在原位置"); return }
        for url in targets { NSWorkspace.shared.open(url) }
    }

    @objc func reveal() {
        let targets = item.liveMemberURLs
        guard !targets.isEmpty else { NSSound.beep(); return }
        NSWorkspace.shared.activateFileViewerSelecting(targets)
    }

    @objc func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.isGroup {
            _ = pb.writeObjects(item.liveMemberURLs as [NSURL])
        } else if item.kind == .text, let text = item.previewText() {
            pb.setString(text, forType: .string)
        } else if let image = item.image() {
            pb.writeObjects([image])
        } else {
            pb.writeObjects([item.url as NSURL])
        }
    }

    @objc func moveToHead() {
        Store.shared.move(id: item.id, to: 0)
        scrollIntoView(0)
        refresh()
    }

    @objc func moveToTail() {
        let to = Store.shared.items.count - 1
        Store.shared.move(id: item.id, to: to)
        scrollIntoView(to)
        refresh()
    }

    /// 换位后可能跑到屏幕外，把它滑回当前这一屏
    private func scrollIntoView(_ index: Int) {
        (view as? LineView)?.revealSlot(index)
    }

    @objc func rename() {
        let alert = NSAlert()
        alert.messageText = "重命名"
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = item.displayName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { item.displayName = name; Store.shared.save() }
            refresh()
        }
    }

    @objc func remove() {
        Store.shared.remove(item)
        refresh()
    }

    @objc func rehookOriginal() {
        let targets = item.liveMemberURLs
        guard !targets.isEmpty else { return }
        _ = Store.shared.stash(urls: targets, preferredIndex: 0)
        refresh()
    }

    private func note(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.informativeText = item.url.path
        alert.runModal()
    }

    /// 分组衣架的一行说明
    var subtitleText: String {
        if item.isGroup {
            let names = item.members.map { $0.url.lastPathComponent }
            return names.joined(separator: "、")
        }
        return item.fileExists ? item.url.path : "文件已丢失"
    }
}

final class RetainingMenu: NSMenu {
    var keeper: AnyObject?
}

enum ContextMenu {
    static func menu(for item: ShelfItem, index: Int, view: NSView?) -> NSMenu {
        let actions = ItemActions(item, view: view)
        let menu = RetainingMenu()
        menu.keeper = actions

        func add(_ title: String, _ sel: Selector) {
            menu.addItem(withTitle: title, action: sel, keyEquivalent: "").target = actions
        }
        add("打开", #selector(ItemActions.open))
        add("在 Finder 中显示", #selector(ItemActions.reveal))
        add("内容复制到剪贴板", #selector(ItemActions.copyToClipboard))
        menu.addItem(.separator())
        add("移到最左", #selector(ItemActions.moveToHead))
        add("移到最右", #selector(ItemActions.moveToTail))
        add("重命名…", #selector(ItemActions.rename))
        if index > 0 {
            add("复制一份新衣架", #selector(ItemActions.rehookOriginal))
        }
        menu.addItem(.separator())
        add("取下", #selector(ItemActions.remove))
        return menu
    }
}

// MARK: - 预览浮层

final class PreviewController {
    static let shared = PreviewController()
    private let popover = NSPopover()
    private var shownItemID: UUID?

    var isShown: Bool { popover.isShown }

    func close() {
        guard popover.isShown else { return }
        shownItemID = nil
        popover.performClose(nil)
    }

    func toggle(item: ShelfItem, anchor: NSRect, in window: NSWindow, view: NSView) {
        if popover.isShown, shownItemID == item.id {
            popover.performClose(nil); shownItemID = nil; return
        }
        shownItemID = item.id
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = PreviewViewController(item: item, actions: ItemActions(item, view: view))
        popover.show(relativeTo: anchor, of: view, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

private final class PreviewViewController: NSViewController {
    private let item: ShelfItem
    private let actions: ItemActions

    init(item: ShelfItem, actions: ItemActions) {
        self.item = item
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let width: CGFloat = 300
        let mediaHeight: CGFloat = 190
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: mediaHeight + 108))
        root.autoresizingMask = [.width, .height]

        let mediaFrame = NSRect(x: 10, y: root.bounds.height - mediaHeight - 10,
                                width: width - 20, height: mediaHeight)
        if item.kind == .text, let text = item.previewText() {
            let scroll = NSScrollView(frame: mediaFrame)
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = true
            scroll.backgroundColor = NSColor.textBackgroundColor
            let tv = NSTextView(frame: scroll.bounds)
            tv.isEditable = false
            tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            tv.string = text
            tv.textContainerInset = NSSize(width: 6, height: 6)
            tv.isVerticallyResizable = true
            tv.textContainer?.widthTracksTextView = true
            scroll.documentView = tv
            root.addSubview(scroll)
        } else if let image = item.image() {
            let iv = NSImageView(frame: mediaFrame)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.image = image
            iv.imageAlignment = .alignCenter
            root.addSubview(iv)
        } else {
            let iv = NSImageView(frame: mediaFrame)
            iv.image = item.systemIcon()
            iv.imageScaling = .scaleProportionallyDown
            root.addSubview(iv)
        }

        let name = NSTextField(labelWithString: item.displayName)
        name.font = NSFont.boldSystemFont(ofSize: 12)
        name.lineBreakMode = .byTruncatingMiddle
        name.frame = NSRect(x: 12, y: mediaFrame.minY - 24, width: width - 24, height: 18)
        name.autoresizingMask = [.minYMargin, .width]
        root.addSubview(name)

        let path = NSTextField(labelWithString: actions.subtitleText)
        path.font = NSFont.systemFont(ofSize: 10)
        path.textColor = .secondaryLabelColor
        path.lineBreakMode = .byTruncatingMiddle
        path.maximumNumberOfLines = 2
        path.frame = NSRect(x: 12, y: mediaFrame.minY - 54, width: width - 24, height: 30)
        path.autoresizingMask = [.minYMargin, .width]
        root.addSubview(path)

        let stack = NSStackView(views: [
            button("打开", #selector(ItemActions.open)),
            button("复制内容", #selector(ItemActions.copyToClipboard)),
            button("重命名", #selector(ItemActions.rename)),
            button("取下", #selector(ItemActions.remove), tint: true)
        ])
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.frame = NSRect(x: 10, y: 10, width: width - 20, height: 30)
        stack.autoresizingMask = [.minYMargin, .width]
        root.addSubview(stack)

        view = root
        preferredContentSize = root.frame.size
    }

    private func button(_ title: String, _ sel: Selector, tint: Bool = false) -> NSButton {
        let b = NSButton(title: title, target: actions, action: sel)
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = NSFont.systemFont(ofSize: 11)
        if tint { b.contentTintColor = .systemRed }
        return b
    }
}
