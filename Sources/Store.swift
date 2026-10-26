import AppKit
import UniformTypeIdentifiers

enum ItemKind: String, Codable {
    case image
    case text
    case pdf
    case other
}

/// 衣架上挂的一件东西；一个衣架可以挂多件（分组）
struct Member {
    var url: URL
    var isReference: Bool
    var kind: ItemKind
}

final class ShelfItem {
    let id: UUID
    var displayName: String
    var url: URL
    /// true = 直接引用原始位置（大文件不复制）
    var isReference: Bool
    var kind: ItemKind
    var addedAt: Date = Date()
    /// 挂在这个衣架上的全部东西，至少一个
    var members: [Member]

    weak var thumbCacheOwner: Store?
    private var thumb: NSImage?
    private var textPreview: String?

    init(id: UUID = UUID(), displayName: String, url: URL, isReference: Bool, kind: ItemKind) {
        self.id = id
        self.displayName = displayName
        self.url = url
        self.isReference = isReference
        self.kind = kind
        self.members = [Member(url: url, isReference: isReference, kind: kind)]
    }

    init(id: UUID = UUID(), displayName: String, members: [Member]) {
        self.id = id
        self.displayName = displayName
        self.members = members
        let first = members[0]
        self.url = first.url
        self.isReference = first.isReference
        self.kind = first.kind
    }

    var isGroup: Bool { members.count > 1 }
    var memberCount: Int { members.count }
    var memberURLs: [URL] { members.map { $0.url } }
    var liveMemberURLs: [URL] { members.filter { $0.url.isFileURL && FileManager.default.fileExists(atPath: $0.url.path) }.map { $0.url } }

    var fileExists: Bool { FileManager.default.fileExists(atPath: url.path) }

    func image() -> NSImage? {
        if let thumb { return thumb }
        guard fileExists else { return nil }
        let img: NSImage?
        switch kind {
        case .image, .pdf:
            let loaded = NSImage(contentsOf: url)
            if let loaded, loaded.size.width > 2, loaded.size.height > 2 { img = loaded } else { img = nil }
        default:
            img = nil
        }
        thumb = img
        return img
    }

    func systemIcon() -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    func previewText() -> String? {
        if let textPreview { return textPreview }
        guard kind == .text, fileExists else { return nil }
        let raw = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        textPreview = trimmed.isEmpty ? nil : String(trimmed.prefix(1200))
        return textPreview
    }

    /// 供拖出使用：文件不存在时返回 nil
    var usableURL: URL? { fileExists ? url : nil }

    var extBadge: String {
        url.pathExtension.uppercased()
    }
}

struct MemberRecord: Codable {
    let path: String
    let isReference: Bool
    let kind: ItemKind
}

struct Record: Codable {
    let id: UUID
    let name: String
    let path: String
    let isReference: Bool
    let kind: ItemKind
    var members: [MemberRecord]?
}

final class Store {
    static let shared = Store()

    private(set) var items: [ShelfItem] = []

    let rootDir: URL
    let itemsDir: URL
    private var manifest: URL { rootDir.appendingPathComponent("manifest.json") }

    private init() {
        // 自检/测试用 CLOTHESLINE_STORE_DIR 指向独立目录，避免误伤用户真实数据
        if let override = ProcessInfo.processInfo.environment["CLOTHESLINE_STORE_DIR"], !override.isEmpty {
            rootDir = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            rootDir = base.appendingPathComponent("Clothesline", isDirectory: true)
        }
        itemsDir = rootDir.appendingPathComponent("Items", isDirectory: true)
        try? FileManager.default.createDirectory(at: itemsDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: manifest),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return }
        items = records.compactMap { r in
            guard let kind = ItemKind(rawValue: r.kind.rawValue) else { return nil }
            if let list = r.members, !list.isEmpty {
                let members = list.compactMap { m -> Member? in
                    guard let k = ItemKind(rawValue: m.kind.rawValue) else { return nil }
                    return Member(url: URL(fileURLWithPath: m.path), isReference: m.isReference, kind: k)
                }
                guard !members.isEmpty else { return nil }
                return ShelfItem(id: r.id, displayName: r.name, members: members)
            }
            return ShelfItem(id: r.id, displayName: r.name,
                             url: URL(fileURLWithPath: r.path),
                             isReference: r.isReference, kind: kind)
        }
    }

    func save() {
        let records = items.map { item in
            Record(id: item.id, name: item.displayName, path: item.url.path,
                   isReference: item.isReference, kind: item.kind,
                   members: item.members.map { MemberRecord(path: $0.url.path, isReference: $0.isReference,
                                                            kind: $0.kind) })
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: manifest, options: .atomic)
    }

    // MARK: - 操作

    @discardableResult
    func append(_ item: ShelfItem) -> ShelfItem {
        items.append(item)
        save()
        return item
    }

    func insert(_ item: ShelfItem, at index: Int) {
        let clamped = min(max(index, 0), items.count)
        items.insert(item, at: clamped)
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        for member in item.members where !member.isReference {
            try? FileManager.default.removeItem(at: member.url)
        }
        save()
    }

    func removeAll() {
        for item in items {
            for member in item.members where !member.isReference {
                try? FileManager.default.removeItem(at: member.url)
            }
        }
        items = []
        save()
    }

    func move(id: UUID, to index: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: from)
        let target = min(max(index, 0), items.count)
        items.insert(item, at: target)
        save()
    }

    func index(of id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    private func place(_ item: ShelfItem, at index: Int?) {
        if let index { insert(item, at: index) } else { append(item) }
    }

    // MARK: - 收纳

    /// 把外部文件挂上衣架：默认复制进沙盒目录，超大文件只引用原位置
    func stash(from src: URL, preferredIndex: Int? = nil) -> ShelfItem? {
        guard let member = ingest(src) else { return nil }
        let item = ShelfItem(displayName: displayName(for: member), url: member.url,
                             isReference: member.isReference, kind: member.kind)
        place(item, at: preferredIndex)
        return item
    }

    /// 一次拖来多个文件/文件夹：合并成一件，只占一个衣架
    func stash(urls: [URL], preferredIndex: Int? = nil) -> ShelfItem? {
        let present = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !present.isEmpty else { return nil }
        if present.count == 1 { return stash(from: present[0], preferredIndex: preferredIndex) }

        var collected: [Member] = []
        for src in present {
            if let m = ingest(src) { collected.append(m) }
        }
        guard let first = collected.first else { return nil }
        guard collected.count > 1 else {
            let item = ShelfItem(displayName: displayName(for: first), url: first.url,
                                 isReference: first.isReference, kind: first.kind)
            place(item, at: preferredIndex)
            return item
        }
        let item = ShelfItem(displayName: groupTitle(for: first, count: collected.count), members: collected)
        place(item, at: preferredIndex)
        return item
    }

    /// 把一件外部东西收进晾衣架目录（不放进列表）
    private func ingest(_ src: URL) -> Member? {
        let kind = Self.classify(src)
        let isDir = (try? src.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir { return zipFolder(src) }

        let size = (try? src.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 64 * 1024 * 1024 || src.path.hasPrefix(itemsDir.path) {
            return Member(url: src, isReference: true, kind: kind)
        }
        let ext = src.pathExtension
        let dst = itemsDir.appendingPathComponent(stagedName(for: src, ext: ext))
        do {
            try FileManager.default.copyItem(at: src, to: dst)
            return Member(url: dst, isReference: false, kind: kind)
        } catch {
            return Member(url: src, isReference: true, kind: kind)
        }
    }

    /// 复制进 Items/ 时保留原始文件名（Finder 式重名加序号），
    /// 这样衣架上显示的名字、拖出去落到别处的名字都和用户预期一致
    private func stagedName(for src: URL, ext: String) -> String {
        stagedName(base: src.deletingPathExtension().lastPathComponent, ext: ext)
    }

    private func stagedName(base raw: String, ext: String) -> String {
        var safe = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        // 调用方常常已经带了 .png / .txt，别再重复一次
        if safe.lowercased().hasSuffix(".\(ext.lowercased())") {
            safe = String(safe.dropLast(ext.count + 1))
        }
        let base = safe.isEmpty ? "未命名" : safe
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var candidate = base + suffix
        var n = 2
        while FileManager.default.fileExists(atPath: itemsDir.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(n)\(suffix)"
            n += 1
        }
        return candidate
    }

    private func zipFolder(_ src: URL) -> Member {
        let zip = itemsDir.appendingPathComponent(stagedName(for: src, ext: "zip"))
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-c", "-k", src.path, zip.path]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return Member(url: src, isReference: true, kind: .other)
        }
        guard task.terminationStatus == 0, FileManager.default.fileExists(atPath: zip.path) else {
            return Member(url: src, isReference: true, kind: .other)
        }
        return Member(url: zip, isReference: false, kind: .other)
    }

    /// 挂在衣架上的名字 = 拖出去会落地的文件名，两者始终一致
    private func displayName(for member: Member) -> String { member.url.lastPathComponent }

    private func groupTitle(for first: Member, count: Int) -> String {
        "\(first.url.lastPathComponent) 等 \(count) 项"
    }

    /// 把图片数据存成 png 并挂上
    func stash(image data: Data, name: String, at index: Int? = nil) -> ShelfItem? {
        let dst = itemsDir.appendingPathComponent(stagedName(base: name.isEmpty ? "图片" : name, ext: "png"))
        do { try data.write(to: dst, options: .atomic) } catch { return nil }
        let item = ShelfItem(displayName: dst.lastPathComponent, url: dst, isReference: false, kind: .image)
        place(item, at: index)
        return item
    }

    /// 把文本存成 txt 并挂上
    func stash(text: String, name: String, at index: Int? = nil) -> ShelfItem? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let short = String(clean.prefix(24)).replacingOccurrences(of: "\n", with: " ")
        let dst = itemsDir.appendingPathComponent(stagedName(base: name.isEmpty ? short : name, ext: "txt"))
        do { try clean.write(to: dst, atomically: true, encoding: .utf8) } catch { return nil }
        let item = ShelfItem(displayName: dst.lastPathComponent, url: dst, isReference: false, kind: .text)
        place(item, at: index)
        return item
    }

    static func classify(_ url: URL) -> ItemKind {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .text) || type.conforms(to: .plainText) || type.conforms(to: .sourceCode) { return .text }
        }
        return .other
    }
}
