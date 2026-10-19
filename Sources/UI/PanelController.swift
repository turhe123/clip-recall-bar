import AppKit
import Combine
import SwiftUI

/// View state for the history popup: search query, selection and the filtered, scored results.
final class PanelModel: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    @Published private(set) var results: [ClipEntry] = []
    @Published private(set) var totalCount = 0
    @Published var focusToken = 0
    private var cancellables = Set<AnyCancellable>()

    init(store: HistoryStore = .shared) {
        store.$entries
            .combineLatest($query)
            .map { entries, query in Self.filter(entries, query: query) }
            .sink { [weak self] results in
                guard let self else { return }
                self.results = results
                self.selection = min(self.selection, max(results.count - 1, 0))
            }
            .store(in: &cancellables)
        store.$entries.map(\.count).assign(to: \.totalCount, on: self).store(in: &cancellables)
        $query.removeDuplicates().dropFirst().sink { [weak self] _ in self?.selection = 0 }.store(in: &cancellables)
    }

    var selected: ClipEntry? { results.indices.contains(selection) ? results[selection] : nil }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    /// Pinned first; with a query, case-insensitive substring matches outrank fuzzy subsequence matches.
    static func filter(_ entries: [ClipEntry], query: String) -> [ClipEntry] {
        let ordered = entries.filter(\.pinned) + entries.filter { !$0.pinned }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return ordered }
        let scored = ordered.enumerated().compactMap { index, entry -> (Int, Int, Int, ClipEntry)? in
            guard let score = score(entry, needle) else { return nil }
            return (entry.pinned ? 1 : 0, score, -index, entry)
        }
        return scored.sorted { ($0.0, $0.1, $0.2) > ($1.0, $1.1, $1.2) }.map(\.3)
    }

    private static func score(_ entry: ClipEntry, _ needle: String) -> Int? {
        let haystack = entry.kind == .image ? entry.preview : entry.text
        if let range = haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
            let offset = haystack[haystack.startIndex..<range.lowerBound].prefix(900).count
            return 1000 - offset
        }
        let preview = entry.preview.lowercased()
        var score = 0
        var cursor = preview.startIndex
        var last: String.Index?
        for character in needle {
            guard let found = preview[cursor...].firstIndex(of: character) else { return nil }
            if let last, preview.index(after: last) == found { score += 5 } else { score += 1 }
            last = found
            cursor = preview.index(after: found)
        }
        return score
    }
}

/// Borderless panel that may become key without activating the app.
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        PanelController.shared.hide()
    }
}

/// Owns the floating history panel, positions it near the pointer and routes its keyboard shortcuts.
final class PanelController {
    static let shared = PanelController()
    static let size = NSSize(width: 420, height: 480)

    let model = PanelModel()
    private var panel: HistoryPanel?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.query = ""
        model.selection = 0
        panel.setFrame(NSRect(origin: originNearMouse(), size: Self.size), display: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusToken += 1
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
    }

    func paste(_ entry: ClipEntry, plain: Bool) {
        let target = previousApp
        hide()
        PasteService.paste(entry, plain: plain, into: target)
    }

    func openSettings() {
        hide()
        SettingsWindowController.shared.show()
    }

    private func makePanel() -> HistoryPanel {
        let panel = HistoryPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: HistoryView(model: model))
        return panel
    }

    private func originNearMouse() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let size = Self.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
            origin.y = min(max(origin.y, frame.minY + 8), frame.maxY - size.height - 8)
        }
        return origin
    }

    /// Returns nil for events we consume.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let panel, panel.isKeyWindow else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: // Escape
            hide()
            return nil
        case 125: model.move(1); return nil   // Down
        case 126: model.move(-1); return nil  // Up
        case 36, 76: // Return / Enter
            if let entry = model.selected { paste(entry, plain: flags.contains(.option)) }
            return nil
        case 117: deleteSelected(); return nil // Forward delete
        case 51 where flags.contains(.command) || model.query.isEmpty: // Backspace
            deleteSelected()
            return nil
        default:
            break
        }
        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else { return event }
        if key == "p" {
            if let entry = model.selected { HistoryStore.shared.togglePin(entry.id) }
            return nil
        }
        if key == "," {
            openSettings()
            return nil
        }
        if let digit = Int(key), (1...9).contains(digit) {
            if model.results.indices.contains(digit - 1) {
                paste(model.results[digit - 1], plain: flags.contains(.option))
            }
            return nil
        }
        return event
    }

    private func deleteSelected() {
        if let entry = model.selected { HistoryStore.shared.delete(entry.id) }
    }
}
