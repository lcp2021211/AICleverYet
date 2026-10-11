import Foundation

public protocol RadarFetching: Sendable {
    func efficiency() async throws -> Efficiency
    func history() async throws -> History
}

public enum RadarError: LocalizedError {
    case http(Int), invalid, tooLarge
    public var errorDescription: String? {
        switch self {
        case .http(let code): return "数据源暂不可用（HTTP \(code)）"
        case .invalid: return "数据源格式发生变化"
        case .tooLarge: return "数据超过大小限制"
        }
    }
}

public actor RadarClient: BenchFetching {
    private var binding: BenchBinding?
    private var bindingFetchedAt: Date?
    private let session: URLSession

    public init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 18
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session ?? URLSession(configuration: config)
    }

    // Kept for fixture clients; production uses one selected-model batch.
    public func efficiency() async throws -> Efficiency {
        let batch = try await bench(model: nil)
        var result = batch.catalog
        result.points = batch.points
        guard !result.points.isEmpty else { throw RadarError.invalid }
        return result
    }
    public func history() async throws -> History { throw RadarError.invalid }

    public func bench(model: String?) async throws -> BenchBatch {
        let current: BenchBinding
        if let binding, let date = bindingFetchedAt, (0..<3600).contains(Date().timeIntervalSince(date)) {
            current = binding
        } else {
            current = try await fetch(URL(string: "https://codexradar.com/data/radar-bench-binding.json")!)
            try current.validate()
            binding = current
            bindingFetchedAt = Date()
        }
        let model = current.modelEfforts.contains(where: { $0.model == model }) ? model! : current.activeDisplaySelection.model
        let selections = current.modelEfforts.filter { $0.model == model }
        var points: [ModelPoint] = []
        var history: History = [:]
        var failures: [String: String] = [:]
        // At most two requests in flight. Never fetch every model in the catalog.
        for start in stride(from: 0, to: selections.count, by: 2) {
            try Task.checkCancellation()
            let first = selections[start]
            let second = start + 1 < selections.count ? selections[start + 1] : nil
            async let a = read(first, binding: current)
            async let b = read(second, binding: current)
            let results = await [a, b]
            try Task.checkCancellation()
            for result in results.compactMap({ $0 }) {
                switch result {
                case .success(let value):
                    points.append(value.0)
                    history[value.0.id] = value.1
                case .failure(let failure): failures[failure.id] = failure.message
                }
            }
        }
        return BenchBatch(catalog: current.catalog, model: model, points: points, history: history, failures: failures)
    }

    private struct ReadFailure: Error { let id: String; let message: String }
    private func read(_ selection: BenchSelection?, binding: BenchBinding) async -> Result<(ModelPoint, [HistoryPoint]), ReadFailure>? {
        guard let selection else { return nil }
        var url = URLComponents(string: "https://codexradar.com/api/radar-bench-score")!
        url.queryItems = [URLQueryItem(name: "model", value: selection.model), URLQueryItem(name: "effort", value: selection.effort),
                          URLQueryItem(name: "view", value: "summary"), URLQueryItem(name: "selection", value: "user-selected-v1")]
        do {
            let result: BenchSummary = try await fetch(url.url!)
            return .success(try result.project(binding: binding, selection: selection))
        } catch { return .failure(ReadFailure(id: selection.id, message: error.localizedDescription)) }
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AICleverYet/1.2 (macOS)", forHTTPHeaderField: "User-Agent")
        // Streaming enforces the limit before an unexpectedly large response is buffered.
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw RadarError.invalid }
        guard (200...299).contains(http.statusCode) else { throw RadarError.http(http.statusCode) }
        let limit = 4 * 1024 * 1024
        guard response.expectedContentLength <= limit else { throw RadarError.tooLarge }
        var data = Data()
        data.reserveCapacity(max(0, min(Int(response.expectedContentLength), limit)))
        for try await byte in bytes {
            guard data.count < limit else { throw RadarError.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        do { return try RadarJSON.decoder().decode(T.self, from: data) }
        catch {
            #if DEBUG
            print("Radar decode failed (\(url.path)): \(error)")
            #endif
            throw RadarError.invalid
        }
    }
}
