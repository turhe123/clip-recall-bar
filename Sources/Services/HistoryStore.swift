import Foundation

/// Owns the clipboard history: ordering, de-duplication, trimming, pinning and on-disk persistence.
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    /// Newest first. Use `sorted` for display order (pinned first).
    @Published private(set) var entries: [ClipEntry] = []

    let folder: URL
    let imagesFolder: URL
    private var historyURL: URL { folder.appendingPathComponent("history.json") }
    private let ioQueue = DispatchQueue(label: "com.turhe123.cliprecallbar.io", qos: .utility)

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        folder = base.appendingPathComponent("ClipRecallBar", isDirectory: true)
        imagesFolder = folder.appendingPathComponent("Images", isDirectory: true)
        try? fm.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        load()
        pruneOrphanImages()
    }

    var maxEntries: Int {
        let value = UserDefaults.standard.integer(forKey: "historySize")
        return value == 0 ? 200 : min(max(value, 20), 999)
    }

    var sorted: [ClipEntry] { entries.filter(\.pinned) + entries.filter { !$0.pinned } }

    func imageURL(for entry: ClipEntry) -> URL? {
        entry.imageName.map { imagesFolder.appendingPathComponent($0) }
    }

    /// Inserts a new entry at the top, moving an existing duplicate instead of repeating it.
    func add(_ newEntry: ClipEntry, imageData: Data?) {
        var entry = newEntry
        if let index = entries.firstIndex(where: { $0.signature == entry.signature }) {
            let old = entries.remove(at: index)
            entry.pinned = old.pinned
            if entry.kind == .image { entry.imageName = old.imageName }
        } else if let data = imageData, let url = imageURL(for: entry) {
            ioQueue.async { try? data.write(to: url, options: .atomic) }
        }
        entries.insert(entry, at: 0)
        trim()
        save()
    }

    /// Moves an entry to the top (used after pasting it).
    func touch(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        entry.date = Date()
        entries.insert(entry, at: 0)
        save()
    }

    func togglePin(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].pinned.toggle()
        save()
    }

    func delete(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        removeFiles(for: [entries.remove(at: index)])
        save()
    }

    /// Clears everything except pinned entries.
    func clearUnpinned() {
        removeFiles(for: entries.filter { !$0.pinned })
        entries.removeAll { !$0.pinned }
        save()
    }

    /// Drops the oldest unpinned entries beyond the configured history size.
    func trim() {
        var excess = entries.count - maxEntries
        guard excess > 0 else { return }
        var removed: [ClipEntry] = []
        for index in entries.indices.reversed() where excess > 0 && !entries[index].pinned {
            removed.append(entries.remove(at: index))
            excess -= 1
        }
        removeFiles(for: removed)
        save()
    }

    // MARK: Persistence

    private func save() {
        let snapshot = entries
        let url = historyURL
        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            entries = try decoder.decode([ClipEntry].self, from: data)
        } catch {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let aside = folder.appendingPathComponent("history.corrupt-\(formatter.string(from: Date())).json")
            try? FileManager.default.moveItem(at: historyURL, to: aside)
            entries = []
        }
    }

    private func removeFiles(for removed: [ClipEntry]) {
        let urls = removed.compactMap { imageURL(for: $0) }
        guard !urls.isEmpty else { return }
        ioQueue.async { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
    }

    private func pruneOrphanImages() {
        let referenced = Set(entries.compactMap(\.imageName))
        let folder = imagesFolder
        ioQueue.async {
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in files where !referenced.contains(name) {
                try? fm.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }
}
