// Developer-only, offline visual QA. Normal app launch never reads fixtures.
import AppKit
import SwiftUI
import RadarCore

private struct PreviewClient: RadarFetching {
    let directory: URL
    func efficiency() async throws -> Efficiency {
        try RadarJSON.decoder().decode(Efficiency.self, from: Data(contentsOf: directory.appendingPathComponent("efficiency.json")))
    }
    func history() async throws -> History {
        try RadarJSON.decoder().decode(History.self, from: Data(contentsOf: directory.appendingPathComponent("history.json")))
    }
}

@MainActor enum PreviewRenderer {
    static func run() {
        Task { @MainActor in
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: "--render-preview"), args.count > index + 2 else { exit(2) }
            let fixtures = URL(fileURLWithPath: args[index + 1])
            let output = URL(fileURLWithPath: args[index + 2])
            let suite = "com.local.gptiq.preview.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let store = RadarStore(client: PreviewClient(directory: fixtures), cacheURL: nil, defaults: defaults)
            defer { defaults.removePersistentDomain(forName: suite) }
            store.opened()
            while store.isLoading { try? await Task.sleep(nanoseconds: 10_000_000) }
            store.closed()
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    try await render(PanelView(store: store, quit: {}), name: name, appearance: appearance, output: output)
                }
                if let point = store.points.first(where: { $0.id == "gpt-6-astra@max" }) {
                    try await render(TrendCard(point: point, series: HistoryMath.series(in: store.history, for: point)), name: "trend", appearance: .aqua, output: output)
                }
                for harness in [Harness.claudeCode, .dsh, .kiro] {
                    store.selectHarness(harness)
                    try await render(PanelView(store: store, quit: {}), name: harness.rawValue, appearance: .aqua, output: output)
                }
                exit(0)
            } catch { print(error); exit(1) }
        }
    }

    private static func render<V: View>(_ content: V, name: String, appearance: NSAppearance.Name, output: URL) async throws {
        let view = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = view
        view.setFrameSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(3) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(4) }
        try data.write(to: output.appendingPathComponent("preview-\(name).png"))
        print("Rendered \(name): \(view.bounds.size)")
    }
}
