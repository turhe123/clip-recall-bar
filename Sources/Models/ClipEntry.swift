import Foundation

/// The kind of content a history entry holds.
enum ClipKind: String, Codable {
    case text, file, image

    var symbol: String {
        switch self {
        case .text: return "doc.plaintext"
        case .file: return "doc"
        case .image: return "photo"
        }
    }
}

/// A single captured clipboard item. Persisted as JSON; image bytes live in separate PNG files.
struct ClipEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ClipKind
    /// Plain text, or newline-separated file paths for `.file` entries.
    var text: String
    var rtf: Data?
    var imageName: String?
    var imageSize: String?
    var imageHash: String?
    var sourceBundleID: String?
    var date = Date()
    var pinned = false

    init(kind: ClipKind, text: String, rtf: Data? = nil, imageName: String? = nil,
         imageSize: String? = nil, imageHash: String? = nil, sourceBundleID: String?) {
        self.kind = kind
        self.text = text
        self.rtf = rtf
        self.imageName = imageName
        self.imageSize = imageSize
        self.imageHash = imageHash
        self.sourceBundleID = sourceBundleID
    }

    /// Fingerprint used to detect duplicates.
    var signature: String {
        switch kind {
        case .text: return "t:" + text
        case .file: return "f:" + text
        case .image: return "i:" + (imageHash ?? id.uuidString)
        }
    }

    /// One-line preview truncated to 80 characters.
    var preview: String {
        let raw: String
        switch kind {
        case .image:
            raw = "Image" + (imageSize.map { " \($0)" } ?? "")
        case .file:
            let names = text.split(separator: "\n").map { (String($0) as NSString).lastPathComponent }
            raw = names.count > 1 ? "\(names.count) files: " + names.joined(separator: ", ") : (names.first ?? "File")
        case .text:
            raw = String(text.prefix(400))
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .joined(separator: " ")
        }
        return raw.count > 80 ? String(raw.prefix(79)) + "…" : raw
    }

    /// Stable FNV-1a hash, used to de-duplicate images across launches.
    static func fingerprint(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
