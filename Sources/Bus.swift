import AppKit

/// 跨模块刷新通知：在没有 NSApplication 实例的自检环境里也能安全调用
enum Bus {
    static func refresh() {
        guard let app = NSApp else { return }
        app.sendAction(#selector(AppDelegate.refreshInterface(_:)), to: nil, from: nil)
    }
}
