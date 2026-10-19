import AppKit
import Carbon

/// Registers the global "open history" shortcut through Carbon's RegisterEventHotKey (no permission needed).
final class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    @Published var errorMessage: String?
    @Published private(set) var label: String
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false
    private let defaults = UserDefaults.standard

    private init() {
        label = defaults.string(forKey: "hotKeyLabel") ?? "⇧⌘V"
    }

    private var savedKeyCode: UInt32 {
        defaults.object(forKey: "hotKeyCode") == nil
            ? UInt32(kVK_ANSI_V) : UInt32(truncatingIfNeeded: defaults.integer(forKey: "hotKeyCode"))
    }

    private var savedModifiers: UInt32 {
        defaults.object(forKey: "hotKeyMods") == nil
            ? UInt32(cmdKey | shiftKey) : UInt32(truncatingIfNeeded: defaults.integer(forKey: "hotKeyMods"))
    }

    func registerSaved() {
        if !register(keyCode: savedKeyCode, modifiers: savedModifiers) {
            errorMessage = "\(label) is already used by another app. Record a different shortcut."
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    /// Tries a newly recorded shortcut; keeps the previous one if it is taken.
    func update(keyCode: UInt16, flags: NSEvent.ModifierFlags, key: String) {
        let modifiers = Self.carbonModifiers(flags)
        let newLabel = Self.symbols(flags) + key
        if register(keyCode: UInt32(keyCode), modifiers: modifiers) {
            defaults.set(Int(keyCode), forKey: "hotKeyCode")
            defaults.set(Int(modifiers), forKey: "hotKeyMods")
            defaults.set(newLabel, forKey: "hotKeyLabel")
            label = newLabel
            errorMessage = nil
        } else {
            registerSaved()
            errorMessage = "\(newLabel) is already in use. Try another shortcut."
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        installHandler()
        unregister()
        let id = EventHotKeyID(signature: OSType(0x4352_4252), id: 1) // "CRBR"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyManager.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        return UInt32(result)
    }

    private static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }
}
