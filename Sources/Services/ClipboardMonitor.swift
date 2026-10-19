import AppKit

/// Polls the general pasteboard and turns new, allowed content into history entries.
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    static let maxTextBytes = 1_000_000
    static let maxImageBytes = 10_000_000
    private static let concealedType = "org.nspasteboard.ConcealedType"
    private static let transientType = "org.nspasteboard.TransientType"

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private var pending: DispatchWorkItem?

    private init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Marks the current pasteboard contents as our own write so they aren't captured again.
    func ignoreCurrentChange() {
        pending?.cancel()
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Debounce bursts: only capture once the pasteboard has settled.
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pasteboard.changeCount == count else { return }
            self.capture(source: source)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func capture(source: String?) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "pauseCapture") else { return }
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard !types.isEmpty, !types.contains(Self.transientType) else { return }
        let ignoreConcealed = defaults.object(forKey: "ignoreConcealed") as? Bool ?? true
        if ignoreConcealed && types.contains(Self.concealedType) { return }
        if let source, Self.ignoredApps().contains(source) { return }
        if source == Bundle.main.bundleIdentifier { return }

        guard let (entry, imageData) = readEntry(types: types, source: source) else { return }
        HistoryStore.shared.add(entry, imageData: imageData)
        if defaults.bool(forKey: "playSound") { NSSound(named: "Tink")?.play() }
    }

    static func ignoredApps() -> [String] {
        (UserDefaults.standard.string(forKey: "ignoredApps") ?? "")
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func readEntry(types: Set<String>, source: String?) -> (ClipEntry, Data?)? {
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue),
           let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return (ClipEntry(kind: .file, text: urls.map(\.path).joined(separator: "\n"), sourceBundleID: source), nil)
        }

        let rtf = pasteboard.data(forType: .rtf)
        var text = pasteboard.string(forType: .string)
        if text?.isEmpty ?? true, let rtf, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            text = attributed.string
        }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard text.utf8.count <= Self.maxTextBytes else { return nil }
            let keptRTF = (rtf?.count ?? 0) <= Self.maxTextBytes ? rtf : nil
            return (ClipEntry(kind: .text, text: text, rtf: keptRTF, sourceBundleID: source), nil)
        }

        if let raw = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           raw.count <= Self.maxImageBytes * 5,
           let rep = NSBitmapImageRep(data: raw),
           let png = rep.representation(using: .png, properties: [:]),
           png.count <= Self.maxImageBytes {
            let entry = ClipEntry(kind: .image, text: "", imageName: UUID().uuidString + ".png",
                                  imageSize: "\(rep.pixelsWide)×\(rep.pixelsHigh)",
                                  imageHash: ClipEntry.fingerprint(png), sourceBundleID: source)
            return (entry, png)
        }
        return nil
    }
}
