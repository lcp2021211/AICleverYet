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

public actor RadarClient: RadarFetching {
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

    public func efficiency() async throws -> Efficiency {
        let result: Efficiency = try await fetch("intelligence-efficiency")
        guard !result.availablePoints.isEmpty else { throw RadarError.invalid }
        return result
    }

    public func history() async throws -> History {
        let result: History = try await fetch("iq-history")
        // Retain all harnesses, but never mix aggregate or latest: series into trends.
        return result.filter { !$0.key.hasPrefix("latest:") && $0.key.contains("@") }
            .mapValues { $0.filter { (0...150).contains($0.score) && ($0.n ?? 0) > 0 } }
    }

    private func fetch<T: Decodable>(_ endpoint: String) async throws -> T {
        let url = URL(string: "https://api.codexradar.com/api/v1/\(endpoint)")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AICleverYet/1.1 (macOS)", forHTTPHeaderField: "User-Agent")
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
            print("Radar decode failed (\(endpoint)): \(error)")
            #endif
            throw RadarError.invalid
        }
    }
}
