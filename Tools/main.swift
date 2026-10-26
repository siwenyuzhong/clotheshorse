import AppKit

// 自检：验证「收纳 / 拖出载荷 / 换位」这三条核心链路，无需 GUI 自动化
var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ✓ \(msg)" : "  ✗ \(msg)")
    if !cond { failures += 1 }
}

print("[1] 收纳文件")
let fixtureDir = URL(fileURLWithPath: "/tmp/cltest", isDirectory: true)
try? FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
try? "测试文档\n第二行".write(to: fixtureDir.appendingPathComponent("示例笔记.txt"),
                            atomically: true, encoding: .utf8)
let pngURL = fixtureDir.appendingPathComponent("风景.png")
if !FileManager.default.fileExists(atPath: pngURL.path) {
    let img = NSImage(size: NSSize(width: 200, height: 120), flipped: false) { rect in
        NSColor.systemTeal.setFill(); rect.fill(); return true
    }
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: pngURL)
    }
}
let store = Store.shared
store.removeAll()
let txt = URL(fileURLWithPath: "/tmp/cltest/示例笔记.txt")
let png = URL(fileURLWithPath: "/tmp/cltest/风景.png")
guard let textItem = store.stash(from: txt) else { print("  ✗ 文本收纳失败"); exit(1) }
guard let imageItem = store.stash(from: png) else { print("  ✗ 图片收纳失败"); exit(1) }
check(textItem.url.path.hasPrefix(store.itemsDir.path), "文本已复制进衣架目录")
check(textItem.displayName == "示例笔记.txt", "复制后保留原文件名")
check(textItem.displayName == textItem.url.lastPathComponent, "衣架上的名字就是拖出去的文件名")
let dup = store.stash(from: txt)
check(dup?.displayName == "示例笔记 2.txt", "重名自动加序号，不会覆盖")
store.remove(dup!)
check(imageItem.kind == .image, "识别为图片")
check(textItem.kind == .text, "识别为文本")
check(store.items.count == 2, "衣架上挂了 2 件")

print("[2] 拖出载荷（文本）")
let tw = ShelfWriter(item: textItem, slotIndex: 1)
check(tw.fileItems.count == 1, "单件衣架给出 1 个拖拽条目")
let textEntry = tw.fileItems.first
check(textEntry?.types.contains(.fileURL) == true, "声明 file-url 类型")
check(!textEntry!.types.contains(.string), "不再附带正文（拖过去就是文件）")
check(textEntry?.string(forType: .fileURL) == textItem.url.absoluteString, "file-url 指向衣架文件")
check(textEntry?.data(forType: .hangerSlot) != nil, "首个条目带上衣架序号")

print("[3] 拖出载荷（图片）")
let iw = ShelfWriter(item: imageItem, slotIndex: 0)
let imgEntry = iw.fileItems.first
check(!imgEntry!.types.contains(.png) && !imgEntry!.types.contains(.tiff), "不声明图片内容类型")
check(imgEntry?.data(forType: .png) == nil, "png 数据不再提供")
check(imgEntry?.string(forType: .fileURL) == imageItem.url.absoluteString, "file-url 指向衣架里的图片文件")
check(String(data: imgEntry?.data(forType: .hangerSlot) ?? Data(), encoding: .utf8) == "0", "序号载荷正确")
check(iw.makeDraggingItems(frame: NSRect(x: 0, y: 0, width: 10, height: 10), contents: nil).count == 1,
      "单件只开一个拖拽条目")

print("[4] 换位与取下")
store.move(id: imageItem.id, to: 1)
check(store.items.first?.id == textItem.id, "移到最左生效")
store.remove(imageItem)
check(store.items.count == 1, "取下后数量正确")
check(!FileManager.default.fileExists(atPath: imageItem.url.path), "取下时清理了副本文件")

print("[5] 剪贴板收纳")
let pb = NSPasteboard.general
pb.clearContents()
pb.setString("从剪贴板来的段落\n第二行", forType: .string)
ClipboardStash.run()
check(store.items.count == 2, "剪贴板文字挂成了新衣架")
check(store.items.last?.kind == .text, "类型为文本")
let clipName = store.items.last?.displayName ?? ""
check(clipName.hasSuffix(".txt") && !clipName.hasSuffix(".txt.txt"), "剪贴板文件名不会重复扩展名（\(clipName)）")

print("[6] 一次拖多个：合并成一个衣架")
let batch = fixtureDir.appendingPathComponent("一批", isDirectory: true)
try? FileManager.default.removeItem(at: batch)
try? FileManager.default.createDirectory(at: batch.appendingPathComponent("子目录", isDirectory: true),
                                        withIntermediateDirectories: true)
try? "子目录里的东西".write(to: batch.appendingPathComponent("子目录/丙.txt"),
                          atomically: true, encoding: .utf8)
let before = store.items.count
var sources: [URL] = []
for name in ["甲.txt", "乙.md"] {
    let u = batch.appendingPathComponent(name)
    try? "批量内容".write(to: u, atomically: true, encoding: .utf8)
    sources.append(u)
}
sources.append(batch.appendingPathComponent("子目录"))
let group = store.stash(urls: sources)
check(store.items.count == before + 1, "三个来源只多出一个衣架")
check(group?.isGroup == true, "标记为成组")
check(group?.memberCount == 3, "衣架上挂着 3 件")
check(group?.displayName.contains("3 项") == true, "名称写着「等 3 项」")
if let group {
    let writer = ShelfWriter(item: group, slotIndex: 0)
    let payload = writer.fileItems
    check(payload.count == 3, "拖出时给目标应用 3 个文件条目")
    let paths = payload.compactMap { URL(string: $0.string(forType: .fileURL) ?? "")?.path }
    check(paths.count == 3 && paths.allSatisfy { FileManager.default.fileExists(atPath: $0) },
          "3 个文件路径都真实存在")
    let folderEntry = paths.first { $0.hasSuffix(".zip") }
    check(folderEntry != nil, "文件夹打包成了一个 zip")
    let offered = Set(payload.flatMap { $0.types })
    check(offered.isSubset(of: [.fileURL, .hangerSlot]),
          "拖出去只声明文件类型（实际：\(offered.map { $0.rawValue }.sorted().joined(separator: " "))）")
    check(payload.first?.data(forType: .hangerSlot) != nil, "只有首件带上衣架序号")
    check(payload.dropFirst().allSatisfy { $0.data(forType: .hangerSlot) == nil },
          "其余条目不带内部序号")
    let session = writer.makeDraggingItems(frame: NSRect(x: 0, y: 0, width: 10, height: 10), contents: nil)
    check(session.count == 3, "拖拽会话开 3 个条目，整批都能落地")
    store.remove(group)
    check(store.items.count == before, "取下成组衣架后数量回到原样")
    check(store.items.allSatisfy { $0.memberURLs.allSatisfy { url in FileManager.default.fileExists(atPath: url.path) } },
          "没有误删别的衣架的文件")
}

store.removeAll()
print(failures == 0 ? "全部通过" : "\(failures) 项失败")
exit(failures == 0 ? 0 : 1)
