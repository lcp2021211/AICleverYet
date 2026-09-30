import Foundation
import Combine

private struct DiskCache: Codable {
    var version: Int?
    var efficiency: Efficiency?
    var history: History
    var currentFetchedAt: Date?
    var historyFetchedAt: Date?
}

@MainActor public final class RadarStore: ObservableObject {
    @Published public private(set) var snapshot: Efficiency?
    @Published public private(set) var history: History = [:]
    @Published public private(set) var currentFetchedAt: Date?
    @Published public private(set) var historyFetchedAt: Date?
    @Published public private(set) var isLoading = false
    @Published public private(set) var currentError: String?
    @Published public private(set) var historyError: String?
    @Published public private(set) var isOpen = false
    @Published public private(set) var selectedID: String
    public var onChange: (() -> Void)?

    private let client: any RadarFetching
    private let cacheURL: URL?
    private let defaults: UserDefaults
    private let now: () -> Date
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var lastAttempt: Date?
    public static let currentTTL: TimeInterval = 60
    public static let historyTTL: TimeInterval = 15 * 60

    public init(client: any RadarFetching = RadarClient(), cacheURL: URL? = RadarStore.defaultCacheURL,
                defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.cacheURL = cacheURL
        self.defaults = defaults
        self.now = now
        self.selectedID = defaults.string(forKey: "selectedModel") ?? ""
        if let url = cacheURL, let data = try? Data(contentsOf: url), data.count <= 4 * 1024 * 1024,
           let cache = try? JSONDecoder().decode(DiskCache.self, from: data) {
            snapshot = cache.efficiency
            history = cache.history
            currentFetchedAt = cache.currentFetchedAt
            historyFetchedAt = cache.version == 2 ? cache.historyFetchedAt : nil
        }
        normalizeSelection()
        if selected != nil { defaults.set(selectedID, forKey: "selection.\(selectedHarness.rawValue)") }
        // Deliberately no startup fetch, timer, reachability monitor, or background task.
    }

    nonisolated public static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.local.gptiq/snapshot.json")
    }

    public var points: [ModelPoint] { snapshot?.availablePoints ?? [] }
    public var selected: ModelPoint? { points.first { $0.id == selectedID } }
    public var harnesses: [Harness] { Harness.allCases.filter { h in points.contains { $0.harnessKind == h } } }
    public var selectedHarness: Harness { selected?.harnessKind ?? .codex }
    public func models(in harness: Harness) -> [String] {
        // Preserve the source's model order; it puts the primary models first.
        var seen = Set<String>()
        return points.filter { $0.harnessKind == harness && seen.insert($0.model).inserted }.map(\.model)
    }
    public var models: [String] { models(in: selectedHarness) }
    public var efforts: [ModelPoint] {
        let order = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
        return points.filter { $0.model == selected?.model }.sorted {
            (order.firstIndex(of: $0.effort) ?? 99) < (order.firstIndex(of: $1.effort) ?? 99)
        }
    }
    public var bestEffort: ModelPoint? { efforts.filter(\.isRankable).max { ($0.iq ?? 0) < ($1.iq ?? 0) } }
    public var series: [HistoryPoint] {
        guard let selected else { return [] }
        return HistoryMath.series(in: history, for: selected)
    }
    public var isStale: Bool { currentFetchedAt.map { now().timeIntervalSince($0) > Self.currentTTL } ?? true }

    public func select(_ id: String) {
        guard points.contains(where: { $0.id == id }) else { return }
        selectedID = id
        defaults.set(id, forKey: "selectedModel")
        defaults.set(id, forKey: "selection.\(selectedHarness.rawValue)")
        onChange?()
    }

    public func selectHarness(_ harness: Harness) {
        if let remembered = defaults.string(forKey: "selection.\(harness.rawValue)"),
           points.contains(where: { $0.id == remembered && $0.harnessKind == harness }) {
            select(remembered)
        } else if let model = models(in: harness).first { selectModel(model) }
    }

    public func selectModel(_ model: String) {
        let options = points.filter { $0.model == model }
        if let point = options.first(where: { $0.effort == selected?.effort }) ?? options.filter(\.isRankable).max(by: { ($0.iq ?? 0) < ($1.iq ?? 0) }) ?? options.first {
            select(point.id)
        }
    }

    public func opened() {
        isOpen = true
        refresh()
    }

    public func closed() {
        isOpen = false
        generation = UUID()
        // A cancelled first load must be retryable on an immediate reopen.
        if isLoading { lastAttempt = nil }
        task?.cancel()
        task = nil
        isLoading = false
    }

    public func refresh(force: Bool = false) {
        guard isOpen, !isLoading else { return }
        let date = now()
        // Manual retries are bounded too; rapid clicks cannot flood the API.
        if let lastAttempt, date.timeIntervalSince(lastAttempt) < 3 { return }
        let needsCurrent = force || expired(currentFetchedAt, ttl: Self.currentTTL)
        let needsHistory = force || expired(historyFetchedAt, ttl: Self.historyTTL)
        guard needsCurrent || needsHistory else { return }
        lastAttempt = date
        isLoading = true
        let token = UUID()
        generation = token
        task = Task { [weak self] in
            guard let self else { return }
            async let current: Void = needsCurrent ? self.loadCurrent(token) : ()
            async let past: Void = needsHistory ? self.loadHistory(token) : ()
            _ = await (current, past)
            guard self.generation == token, !Task.isCancelled else { return }
            self.isLoading = false
            self.task = nil
            self.persist()
            self.onChange?()
        }
    }

    private func expired(_ date: Date?, ttl: TimeInterval) -> Bool {
        guard let date else { return true }
        let age = now().timeIntervalSince(date)
        return age < 0 || age >= ttl
    }

    private func loadCurrent(_ token: UUID) async {
        do {
            let result = try await client.efficiency()
            guard generation == token, isOpen, !Task.isCancelled else { return }
            guard !result.availablePoints.isEmpty else { throw RadarError.invalid }
            snapshot = result
            currentFetchedAt = now()
            currentError = nil
            normalizeSelection()
            persist()
            onChange?()
        } catch {
            guard generation == token, isOpen, !Task.isCancelled else { return }
            currentError = friendly(error)
        }
    }

    private func loadHistory(_ token: UUID) async {
        do {
            let result = try await client.history()
            guard generation == token, isOpen, !Task.isCancelled else { return }
            history = result
            historyFetchedAt = now()
            historyError = nil
        } catch {
            guard generation == token, isOpen, !Task.isCancelled else { return }
            historyError = friendly(error)
        }
    }

    private func normalizeSelection() {
        guard selected == nil else { return }
        // Prefer the first GPT family published by the source, then its highest IQ.
        guard let first = points.first else { return }
        select(points.filter { $0.model == first.model && $0.isRankable }.max { ($0.iq ?? 0) < ($1.iq ?? 0) }?.id ?? first.id)
    }

    private func persist() {
        guard let url = cacheURL else { return }
        let cache = DiskCache(version: 2, efficiency: snapshot, history: history, currentFetchedAt: currentFetchedAt, historyFetchedAt: historyFetchedAt)
        do {
            let data = try JSONEncoder().encode(cache)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch { /* A disk-cache failure never prevents live display. */ }
    }

    private func friendly(_ error: Error) -> String {
        if let error = error as? RadarError { return error.localizedDescription }
        if (error as? URLError)?.code == .timedOut { return "请求超时，点刷新重试" }
        return "暂时无法连接，点刷新重试"
    }
}
