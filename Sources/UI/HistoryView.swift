import AppKit
import SwiftUI

/// The popup's content: search field, scrolling result list and a bottom status bar.
struct HistoryView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
            }
            .padding(12)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 10) {
                Text("\(model.totalCount) item\(model.totalCount == 1 ? "" : "s")")
                Spacer()
                Text("⏎ paste · ⌥⏎ plain · ⌘P pin").foregroundStyle(.tertiary)
                Button { PanelController.shared.openSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: PanelController.size.width, height: PanelController.size.height)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { searchFocused = true }
    }

    @ViewBuilder private var content: some View {
        if model.totalCount == 0 {
            placeholder("Nothing copied yet", hint: "Copy something and it will show up here.", symbol: "clipboard")
        } else if model.results.isEmpty {
            placeholder("No matches", hint: nil, symbol: "magnifyingglass")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, entry in
                            ClipRow(entry: entry, index: index, selected: index == model.selection)
                                .id(entry.id)
                                .onTapGesture {
                                    model.selection = index
                                    PanelController.shared.paste(entry, plain: false)
                                }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selection) { _, selection in
                    if model.results.indices.contains(selection) {
                        proxy.scrollTo(model.results[selection].id)
                    }
                }
            }
        }
    }

    private func placeholder(_ title: String, hint: String?, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            if let hint { Text(hint).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

/// A single history row: type icon, preview, pin badge, source app icon, relative time and ⌘-digit hint.
struct ClipRow: View {
    let entry: ClipEntry
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.kind.symbol)
                .frame(width: 18)
                .foregroundStyle(selected ? Color.white : Color.secondary)
            Text(entry.preview).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if entry.pinned { Image(systemName: "pin.fill").font(.caption) }
            if let icon = AppIconCache.icon(for: entry.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            Text(entry.date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                .font(.caption)
                .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

/// Caches source-app icons looked up by bundle identifier.
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

/// Behind-window blur used as the panel background.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
