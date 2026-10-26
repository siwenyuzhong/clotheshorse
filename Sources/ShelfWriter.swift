import AppKit

/// 晾衣架内部用于识别「同一个衣架被拖动」的类型
extension NSPasteboard.PasteboardType {
    static let hangerSlot = NSPasteboard.PasteboardType("com.clotheshorse.slot")
}

/// 拖出去的就是文件本身：只声明 file-url（外加晾衣架自己识别换位用的内部序号），
/// 不再附带图片/文字内容，免得落到编辑器里变成粘贴正文而不是放入文件。
/// 分组衣架会为每一件文件各生成一个拖拽条目，拖出去就是当初那一整批。
struct ShelfWriter {

    /// 衣架上每一件还在的文件，各占一个粘贴板条目
    let fileItems: [NSPasteboardItem]

    init(item: ShelfItem, slotIndex: Int) {
        var entries: [NSPasteboardItem] = []
        for url in item.liveMemberURLs {
            let entry = NSPasteboardItem()
            // 数据必须在这里就写进去：惰性 provider 在跨应用拖拽时目标端（访达）会直接判定不可放置
            entry.setString(url.absoluteString, forType: .fileURL)
            entries.append(entry)
        }
        if let first = entries.first {
            first.setData(Data("\(slotIndex)".utf8), forType: .hangerSlot)
        }
        fileItems = entries
    }

    /// 一件文件一个 NSDraggingItem：拖拽会话只认传给 beginDraggingSession 的数组，
    /// 指望单个 writer 展开出多个粘贴板条目是不行的，那样目标应用只会收到第一件
    func makeDraggingItems(frame: NSRect, contents: NSImage?) -> [NSDraggingItem] {
        return fileItems.enumerated().map { i, entry in
            let drag = NSDraggingItem(pasteboardWriter: entry)
            // 尺寸不能为 0（系统会直接抛异常），但拖拽图像只画第一件那一份
            drag.setDraggingFrame(frame, contents: i == 0 ? contents : nil)
            return drag
        }
    }
}
