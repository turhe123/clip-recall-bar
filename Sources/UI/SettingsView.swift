import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

/// Hosts the SwiftUI settings form in a regular AppKit window (menu-bar apps have no main window).
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "ClipRecallBar Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The settings form: history size, shortcut, login item, capture filters and history maintenance.
struct SettingsView: View {
    @AppStorage("historySize") private var historySize = 200
    @AppStorage("playSound") private var playSound = false
    @AppStorage("ignoreConcealed") private var ignoreConcealed = true
    @AppStorage("ignoredApps") private var ignoredAppsRaw = ""
    @ObservedObject private var hotKey = HotKeyManager.shared

    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var newBundleID = ""
    @State private var confirmClear = false
    @State private var axTrusted = AXIsProcessTrusted()

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var ignoredApps: [String] {
        ignoredAppsRaw.split(separator: "\n").map(String.init)
    }

    var body: some View {
        Form {
            Section("History") {
                Stepper("History size: \(historySize) items", value: $historySize, in: 20...999, step: 10)
                    .onChange(of: historySize) { HistoryStore.shared.trim() }
                Button("Clear History…", role: .destructive) { confirmClear = true }
            }

            Section("Shortcut") {
                HotKeyRecorder()
                if let error = hotKey.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { loginStatus == .enabled }, set: setLaunchAtLogin))
                if loginStatus == .requiresApproval {
                    Text("Approve ClipRecallBar in System Settings › General › Login Items.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Play sound on copy", isOn: $playSound)
                Toggle("Ignore items marked as concealed", isOn: $ignoreConcealed)
            }

            Section("Permissions") {
                HStack {
                    Label(axTrusted ? "Accessibility granted — Return pastes directly"
                                    : "Accessibility needed to paste; items are copied only",
                          systemImage: axTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(axTrusted ? Color.green : Color.orange)
                    Spacer()
                    if !axTrusted {
                        Button("Open Settings") { PasteService.openAccessibilitySettings() }
                    }
                }
            }

            Section("Ignored apps") {
                if ignoredApps.isEmpty {
                    Text("No ignored apps").foregroundStyle(.secondary)
                }
                ForEach(ignoredApps, id: \.self) { bundleID in
                    HStack {
                        if let icon = AppIconCache.icon(for: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(bundleID)
                        Spacer()
                        Button { setIgnored(ignoredApps.filter { $0 != bundleID }) } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
                HStack {
                    TextField("Bundle identifier", text: $newBundleID, prompt: Text("com.example.app"))
                        .onSubmit(addIgnored)
                    Button(action: addIgnored) { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.borderless)
                        .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Add")
                }
            }

            Section {
                Button("Support / Donate ❤️") {
                    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { HistoryStore.shared.clearUnpinned() }
        } message: {
            Text("All unpinned items will be removed. Pinned items are kept.")
        }
        .onReceive(refresh) { _ in
            axTrusted = AXIsProcessTrusted()
            loginStatus = SMAppService.mainApp.status
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }

    private func addIgnored() {
        let id = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !ignoredApps.contains(id) else { return }
        setIgnored(ignoredApps + [id])
        newBundleID = ""
    }

    private func setIgnored(_ ids: [String]) {
        ignoredAppsRaw = ids.joined(separator: "\n")
    }
}

/// Click-to-record control for the global shortcut. Requires ⌘, ⌥ or ⌃; Escape cancels.
struct HotKeyRecorder: View {
    @ObservedObject private var manager = HotKeyManager.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text("Open history")
            Spacer()
            Button(recording ? "Type shortcut…" : manager.label) {
                recording ? stop(restore: true) : start()
            }
            .frame(minWidth: 120)
        }
        .onDisappear { if recording { stop(restore: true) } }
    }

    private func start() {
        recording = true
        manager.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 {
            stop(restore: true)
            return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else {
            manager.errorMessage = "Include at least one of ⌘, ⌥ or ⌃."
            return
        }
        let key = event.keyCode == 49 ? "Space" : (event.charactersIgnoringModifiers ?? "?").uppercased()
        manager.update(keyCode: event.keyCode, flags: flags, key: key)
        stop(restore: false)
    }

    private func stop(restore: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        if restore { manager.registerSaved() }
    }
}
