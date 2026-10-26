import AppKit
import Carbon.HIToolbox

/// 全局快捷键（Carbon RegisterEventHotKey，无需辅助功能权限）
final class HotKeys {
    static let shared = HotKeys()

    var onRegionCapture: (() -> Void)?
    var onToggleVisibility: (() -> Void)?
    var onClipboardStash: (() -> Void)?

    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]

    private static let idRegion: UInt32 = 1
    private static let idToggle: UInt32 = 2
    private static let idClipboard: UInt32 = 3

    func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData else { return noErr }
            let me = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let action = me.actions[hkID.id] {
                DispatchQueue.main.async { action() }
                return OSStatus(noErr)
            }
            return OSStatus(eventNotHandledErr)
        }, 1, &spec, nil, &handler)

        register(id: Self.idRegion, keyCode: UInt32(kVK_ANSI_2), mods: UInt32(controlKey | optionKey),
                 action: { [weak self] in self?.onRegionCapture?() })
        register(id: Self.idToggle, keyCode: UInt32(kVK_ANSI_H), mods: UInt32(controlKey | optionKey),
                 action: { [weak self] in self?.onToggleVisibility?() })
        register(id: Self.idClipboard, keyCode: UInt32(kVK_ANSI_V), mods: UInt32(controlKey | optionKey),
                 action: { [weak self] in self?.onClipboardStash?() })
    }

    private func register(id: UInt32, keyCode: UInt32, mods: UInt32, action: @escaping () -> Void) {
        actions[id] = action
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_4853), id: id) // 'CLHS'
        let status = RegisterEventHotKey(keyCode, mods, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        refs.append(status == noErr ? ref : nil)
    }
}
