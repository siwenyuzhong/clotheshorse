import AppKit

enum Capture {

    private static var running = false

    /// 交互式区域截图（系统十字框选），完成后自动挂上
    static func region(into view: NSView? = nil) {
        start(args: ["-i", "-x", "-o", tmpPath()], view: view)
    }

    /// 抓取鼠标所在屏幕的整屏
    static func fullScreen(into view: NSView? = nil) {
        start(args: ["-x", tmpPath()], view: view)
    }

    private static func start(args: [String], view: NSView?) {
        guard !running else { return }
        let path = (args.last ?? "").hasSuffix(".png") ? args.last! : tmpPath()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        running = true
        task.terminationHandler = { proc in
            let ok = proc.terminationStatus == 0
            DispatchQueue.main.async {
                running = false
                finish(ok: ok, path: path, view: view)
            }
        }
        do {
            try task.run()
        } catch {
            running = false
        }
    }

    private static func tmpPath() -> String {
        let stamp = DateFormatter.yyyymmddhhmmss.string(from: Date())
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("截图-\(stamp).png").path
    }

    private static func finish(ok: Bool, path: String, view: NSView?) {
        defer { view?.needsDisplay = true }
        guard ok, FileManager.default.fileExists(atPath: path) else { return }
        let size = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int) ?? 0
        guard size > 0 else { return }
        let url = URL(fileURLWithPath: path)
        guard let item = Store.shared.stash(from: url) else { return }
        if item.url != url { try? FileManager.default.removeItem(at: url) }
        Bus.refresh()
    }
}

enum ClipboardStash {
    static func run(view: NSView? = nil) {
        let pb = NSPasteboard.general
        var added = 0

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            for url in urls where Store.shared.stash(from: url) != nil { added += 1 }
        } else if let data = pb.data(forType: .tiff) ?? pb.data(forType: .png) {
            let stamp = DateFormatter.hhmmss.string(from: Date())
            if Store.shared.stash(image: data, name: "剪贴板图片 \(stamp).png") != nil { added += 1 }
        } else if let text = pb.string(forType: .string) {
            let stamp = DateFormatter.hhmmss.string(from: Date())
            if Store.shared.stash(text: text, name: "剪贴板文字 \(stamp).txt") != nil { added += 1 }
        }
        if added == 0 { NSSound.beep() }
        view?.needsDisplay = true
        Bus.refresh()
    }
}

extension DateFormatter {
    static let yyyymmddhhmmss: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
