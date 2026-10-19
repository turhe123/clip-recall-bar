import AppKit
import SwiftUI

/// App entry point: a menu-bar-only app whose status menu opens the history panel and settings.
@main
struct ClipRecallBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("pauseCapture") private var paused = false

    var body: some Scene {
        MenuBarExtra("ClipRecallBar", systemImage: paused ? "clipboard" : "list.clipboard") {
            Button("Open History") {
                DispatchQueue.main.async { PanelController.shared.show() }
            }
            Toggle("Pause Capture", isOn: $paused)
            Divider()
            Button("Settings…") { SettingsWindowController.shared.show() }
                .keyboardShortcut(",")
            Button("Support / Donate ❤️") {
                NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
            }
            Divider()
            Button("Quit ClipRecallBar") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

/// Wires up services at launch: history store, pasteboard polling, global hotkey and permission check.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = HistoryStore.shared
        ClipboardMonitor.shared.start()
        HotKeyManager.shared.onPress = { PanelController.shared.toggle() }
        HotKeyManager.shared.registerSaved()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { PasteService.checkAtLaunch() }
    }
}
