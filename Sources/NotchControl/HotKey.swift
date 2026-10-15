import AppKit
import Carbon
import ServiceManagement

/// Global keyboard shortcut that toggles the notch. Uses Carbon hot keys, which need no
/// Accessibility permission (unlike NSEvent global key monitors).
final class HotKey {
    struct Combo: Identifiable, Equatable {
        let id: Int
        let title: String
        let keyCode: UInt32
        let modifiers: UInt32
    }

    static let combos: [Combo] = [
        Combo(id: 0, title: "⌥ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
        Combo(id: 1, title: "⌃⌥ N", keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey)),
        Combo(id: 2, title: "⌘⇧ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey)),
        Combo(id: 3, title: "⌃ Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey)),
    ]
    static let enabledKey = "hotkeyEnabled"
    static let comboKey = "hotkeyCombo"

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, selfPtr, &handler)
        apply()
    }

    /// Re-reads the settings and (re)registers the shortcut.
    func apply() {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        let d = UserDefaults.standard
        guard d.bool(forKey: Self.enabledKey) else { return }
        let combo = Self.combos.first { $0.id == d.integer(forKey: Self.comboKey) } ?? Self.combos[0]
        let id = EventHotKeyID(signature: OSType(0x4E544348), id: UInt32(combo.id)) // "NTCH"
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { DebugLog.log("hotkey register failed: \(status)") }
    }
}

/// Start NotchControl when the user logs in (SMAppService, macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
