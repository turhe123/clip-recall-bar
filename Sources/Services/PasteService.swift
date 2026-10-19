import AppKit
import ApplicationServices
import SwiftUI

/// Writes entries back to the pasteboard and synthesises ⌘V into the previously active app.
enum PasteService {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func paste(_ entry: ClipEntry, plain: Bool, into target: NSRunningApplication?) {
        write(entry, plain: plain)
        HistoryStore.shared.touch(entry.id)
        guard isTrusted else {
            Toast.show("Copied — press ⌘V to paste")
            return
        }
        target?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { postCommandV() }
    }

    static func write(_ entry: ClipEntry, plain: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch entry.kind {
        case .text:
            if !plain, let rtf = entry.rtf { pasteboard.setData(rtf, forType: .rtf) }
            pasteboard.setString(entry.text, forType: .string)
        case .file:
            if plain {
                pasteboard.setString(entry.text, forType: .string)
            } else {
                let urls = entry.text.split(separator: "\n").map { NSURL(fileURLWithPath: String($0)) }
                pasteboard.writeObjects(urls)
            }
        case .image:
            if let url = HistoryStore.shared.imageURL(for: entry), let data = try? Data(contentsOf: url) {
                pasteboard.setData(data, forType: .png)
                if let tiff = NSImage(data: data)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
            }
        }
        ClipboardMonitor.shared.ignoreCurrentChange()
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: Accessibility permission

    /// On first launch, explains why Accessibility access is needed and offers to open System Settings.
    static func checkAtLaunch() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        guard !AXIsProcessTrustedWithOptions(options) else { return }
        let key = "didExplainAccessibility"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        explainAccessibility()
    }

    static func explainAccessibility() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Let ClipRecallBar paste for you"
        alert.informativeText = """
        To paste the selected item straight into the app you were using, ClipRecallBar sends a ⌘V keystroke. \
        macOS requires Accessibility permission for that.

        Without it, items are still copied — you just press ⌘V yourself.
        """
        alert.addButton(withTitle: "Open Privacy & Security")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { openAccessibilitySettings() }
    }

    static func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options) // ensures the app is listed in the pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A short-lived HUD banner, used when we can copy but not paste.
enum Toast {
    private static var window: NSPanel?

    static func show(_ message: String) {
        window?.orderOut(nil)
        let host = NSHostingView(rootView:
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
        )
        let size = host.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 120))
        }
        panel.orderFrontRegardless()
        window = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if window === panel {
                panel.orderOut(nil)
                window = nil
            }
        }
    }
}
