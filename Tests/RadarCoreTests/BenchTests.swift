import Foundation
import RadarCore

// Exercise the real URLSession/decoder path without contacting any server.
private final class BenchURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URL] = []
    private static var active = 0
    private static var peak = 0
    private static var failEffort: String?
    private static var mismatch = false
    private static var delay: Double = 0.02
    private var stopped = false
    private var finished = false
    static func configure(fail: String? = nil, mismatch: Bool = false, delay: Double = 0.02, reset: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        failEffort = fail; self.mismatch = mismatch; self.delay = delay
        if reset { requests = []; peak = active }
    }
    static func observed() -> ([URL], Int) { lock.lock(); defer { lock.unlock() }; return (requests, peak) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.lock.lock()
        Self.requests.append(url); Self.active += 1; Self.peak = max(Self.peak, Self.active)
        let fail = Self.failEffort, mismatch = Self.mismatch, delay = Self.delay
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            Self.lock.lock(); defer { Self.lock.unlock() }
            guard !stopped else { return }
            finished = true; Self.active -= 1
            do {
                let binding = url.path.hasSuffix("radar-bench-binding.json")
                let name = binding ? "bench-binding" : "bench-summary"
                let fixture = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
                var data = try Data(contentsOf: fixture)
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let model = query.first { $0.name == "model" }?.value ?? ""
                let effort = query.first { $0.name == "effort" }?.value ?? ""
                if !binding {
                    var value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                    value["model"] = mismatch ? "wrong-model" : model; value["effort"] = effort
                    var history = value["history"] as! [String: Any]
                    history["model"] = model; history["effort"] = effort
                    value["history"] = history
                    if effort == "low" { value["score"] = NSNull(); value["coverage"] = 0; value["graded_runs_count"] = 0; value["score_status"] = "missing_current_result"; value["history"] = NSNull(); value["history_state"] = "unavailable" }
                    data = try JSONSerialization.data(withJSONObject: value)
                }
                let status = !binding && effort == fail ? 503 : 200
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        if !stopped && !finished { Self.active -= 1 }
        stopped = true
    }
}

@MainActor extension RadarChecks {
    private func benchClient() -> RadarClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BenchURLProtocol.self]
        return RadarClient(session: URLSession(configuration: config))
    }
    private func waitBench(_ store: RadarStore) async throws {
        for _ in 0..<500 {
            if !store.isLoading { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        fail("Bench refresh timed out")
    }
    func testBenchTransport() async throws {
        BenchURLProtocol.configure(reset: true)
        let client = benchClient()
        let batch = try await client.bench(model: "gpt-6-astra")
        expectEqual(batch.points.count, 6)
        expectTrue(batch.failures.isEmpty)
        let max = try unwrap(batch.points.first { $0.effort == "max" })
        expectEqual(max.iq, 113.67307692307693)
        expectEqual(max.coverage, 63)
        expectEqual(max.averagePriceUsd, 4.302995936507937)
        expectTrue(abs((max.averageMinutes ?? 0) - 16.876103174603175) < 0.00001)
        expectEqual(batch.history[max.id]?.count, 1)
        expectNil(batch.points.first { $0.effort == "low" }?.iq)
        var observation = BenchURLProtocol.observed()
        expectEqual(observation.0.count, 7)
        expectTrue(observation.1 <= 2)
        expectTrue(observation.0.allSatisfy { $0.host == "codexradar.com" })
        expectFalse(observation.0.contains { $0.path.contains("iq-history") })
        BenchURLProtocol.configure(fail: "high")
        let partial = try await client.bench(model: "gpt-6-astra")
        expectEqual(partial.points.count, 5)
        expectEqual(partial.failures.count, 1)
        observation = BenchURLProtocol.observed()
        expectEqual(observation.0.count, 13) // binding reused; no automatic retries
        BenchURLProtocol.configure(mismatch: true)
        let invalid = try await client.bench(model: "gpt-6-astra")
        expectTrue(invalid.points.isEmpty)
        expectEqual(invalid.failures.count, 6)
    }

    func testBenchStore() async throws {
        BenchURLProtocol.configure(reset: true)
        let client = benchClient()
        let suite = "AICleverYet.bench.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("gpt-6-astra@max", forKey: "selectedModel")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bench-cache-\(UUID()).json")
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: url) }
        var date = Date()
        let store = RadarStore(client: client, cacheURL: url, defaults: defaults, now: { date })
        expectTrue(BenchURLProtocol.observed().0.isEmpty)
        store.refresh(force: true)
        expectTrue(BenchURLProtocol.observed().0.isEmpty)
        store.opened(); try await waitBench(store)
        expectTrue(store.points.allSatisfy(\.isBench))
        expectNotNil(store.selected?.iq)
        let firstModel = store.selected!.model
        let secondModel = firstModel == "gpt-6-astra" ? "gpt-6.1-sol" : "gpt-6-astra"
        let initial = BenchURLProtocol.observed().0.count
        store.selectModel(secondModel); try await waitBench(store)
        expectEqual(BenchURLProtocol.observed().0.count, initial + 6)
        expectNotNil(store.selected?.iq)
        store.selectModel(firstModel); try await waitBench(store)
        expectEqual(BenchURLProtocol.observed().0.count, initial + 6)
        // A model switch cancels the previous batch and rejects its late results.
        BenchURLProtocol.configure(delay: 0.15)
        date = date.addingTimeInterval(65)
        store.refresh(force: true)
        try await Task.sleep(nanoseconds: 30_000_000)
        store.selectModel(secondModel)
        try await waitBench(store)
        expectEqual(store.selected?.model, secondModel)
        expectNil(store.currentError)
        store.selectModel(firstModel)
        try await waitBench(store)
        // Failed refresh preserves that row's score and excludes it from the winner.
        BenchURLProtocol.configure(fail: "max")
        date = date.addingTimeInterval(65)
        store.refresh(force: true); try await waitBench(store)
        let stale = try unwrap(store.efforts.first { $0.effort == "max" })
        expectNotNil(stale.iq); expectNotNil(stale.readError); expectFalse(stale.isRankable)
        store.closed()
        let restored = RadarStore(client: client, cacheURL: url, defaults: defaults)
        expectNotNil(restored.snapshot)
        var old = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        old["version"] = 2
        try JSONSerialization.data(withJSONObject: old).write(to: url)
        let migrated = RadarStore(client: client, cacheURL: url, defaults: defaults)
        expectNil(migrated.snapshot); expectTrue(migrated.history.isEmpty)
        // Close during a load; no queued requests or late writes are accepted.
        BenchURLProtocol.configure(delay: 0.2)
        let before = BenchURLProtocol.observed().0.count
        migrated.opened()
        try await Task.sleep(nanoseconds: 30_000_000)
        migrated.closed()
        try await Task.sleep(nanoseconds: 250_000_000)
        expectNil(migrated.snapshot)
        expectTrue(BenchURLProtocol.observed().0.count <= before + 2)
        BenchURLProtocol.configure()
        migrated.opened(); try await waitBench(migrated)
        expectNotNil(migrated.snapshot)
        migrated.closed()
    }
}
