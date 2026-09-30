import Foundation
import RadarCore

private func fixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try RadarJSON.decoder().decode(type, from: Data(contentsOf: url))
}

private actor StubClient: RadarFetching {
    var currentCalls = 0
    var historyCalls = 0
    var failCurrent = false
    var failHistory = false
    var delay: UInt64 = 0
    var ignoreCancellation = false

    func configure(failCurrent: Bool = false, failHistory: Bool = false, delay: UInt64 = 0, ignoreCancellation: Bool = false) {
        self.failCurrent = failCurrent
        self.failHistory = failHistory
        self.delay = delay
        self.ignoreCancellation = ignoreCancellation
    }
    func counts() -> [Int] { [currentCalls, historyCalls] }
    func efficiency() async throws -> Efficiency {
        currentCalls += 1
        if delay > 0 {
            if ignoreCancellation { try? await Task.sleep(nanoseconds: delay) }
            else { try await Task.sleep(nanoseconds: delay) }
        }
        if failCurrent { throw URLError(.notConnectedToInternet) }
        return try fixture("efficiency")
    }
    func history() async throws -> History {
        historyCalls += 1
        if delay > 0 {
            if ignoreCancellation { try? await Task.sleep(nanoseconds: delay) }
            else { try await Task.sleep(nanoseconds: delay) }
        }
        if failHistory { throw RadarError.http(503) }
        return try fixture("history")
    }
}

@MainActor final class RadarChecks {
    func testRealPayloadAndExactEffortHistory() throws {
        let ungraded = Data("{\"ts\":\"2026-09-30T00:00:00+00:00\",\"score\":null,\"n\":0}".utf8)
        let empty = try RadarJSON.decoder().decode(HistoryPoint.self, from: ungraded)
        expectEqual(empty.score, -1)
        let result: Efficiency = try fixture("efficiency")
        let history: History = try fixture("history")
        let point = try unwrap(result.gptPoints.first { $0.id == "gpt-6-astra@max" })
        expectEqual(point.iq, 108.03)
        expectEqual(point.averagePriceUsd, 4.638413)
        expectEqual(point.priceAggregation, "median")
        expectNotNil(point.sourceUpdatedAt)
        let series = HistoryMath.series(in: history, for: point)
        expectEqual(series.count, 168)
        expectNotEqual(series.last?.score, history["latest:gpt-6-astra@max"]?.last?.score)
        expectNotEqual(series.last?.score, history["gpt-6-astra"]?.last?.score)
        expectNil(HistoryMath.change(Array(series.suffix(4)), hours: 24))
        expectNotNil(HistoryMath.change(series, hours: 24))
        expectEqual(HistoryMath.change(series, hours: 168)?.approximate, true)
    }

    func testHistoryDeltaUsesTimestampAndRequiresCoverage() {
        let date = Date()
        let data = [HistoryPoint(ts: date.addingTimeInterval(-86400), score: 99), HistoryPoint(ts: date, score: 101)]
        expectEqual(HistoryMath.change(data, hours: 24)?.value, 2)
        expectNil(HistoryMath.change(data, hours: 168))
        expectNil(HistoryMath.change([data[1]], hours: 24))
        expectNil(HistoryMath.change([], hours: 24))
    }

    @MainActor private func makeStore(_ client: StubClient, cache: URL? = nil, now: @escaping () -> Date = Date.init) -> RadarStore {
        let defaults = UserDefaults(suiteName: "GPTIQ.tests.\(UUID().uuidString)")!
        return RadarStore(client: client, cacheURL: cache, defaults: defaults, now: now)
    }

    @MainActor private func settle(_ store: RadarStore) async throws {
        for _ in 0..<300 {
            if !store.isLoading { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        fail("Refresh did not finish")
    }

    @MainActor func testNoStartupOrClosedRequestsAndIndependentTTLs() async throws {
        let client = StubClient()
        var date = Date()
        let store = makeStore(client, now: { date })
        store.refresh(force: true)
        var counts = await client.counts()
        expectEqual(counts, [0, 0])
        store.opened()
        store.opened() // In-flight requests are coalesced.
        try await settle(store)
        counts = await client.counts()
        expectEqual(counts, [1, 1])
        store.closed()
        date = date.addingTimeInterval(30)
        store.opened()
        try await settle(store)
        counts = await client.counts()
        expectEqual(counts, [1, 1])
        store.closed()
        date = date.addingTimeInterval(40)
        store.opened()
        try await settle(store)
        counts = await client.counts()
        expectEqual(counts, [2, 1])
        date = date.addingTimeInterval(901)
        // Time passing with panel open still does not trigger any requests.
        counts = await client.counts()
        expectEqual(counts, [2, 1])
        store.closed()
        store.opened()
        try await settle(store)
        counts = await client.counts()
        expectEqual(counts, [3, 2])
    }

    @MainActor func testClosingCancelsAndRejectsLateResult() async throws {
        let client = StubClient()
        await client.configure(delay: 2_000_000_000, ignoreCancellation: true)
        let store = makeStore(client)
        store.opened()
        try await Task.sleep(nanoseconds: 20_000_000)
        store.closed()
        try await Task.sleep(nanoseconds: 100_000_000)
        expectNil(store.snapshot)
        expectTrue(store.history.isEmpty)
        expectFalse(store.isLoading)
        expectNil(store.currentError)
        await client.configure()
        store.opened()
        try await settle(store)
        expectNotNil(store.snapshot)
        store.closed()
    }

    @MainActor func testPartialFailureKeepsCurrentAndDiskCacheSurvivesOffline() async throws {
        let client = StubClient()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gptiq-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var date = Date()
        let store = makeStore(client, cache: url, now: { date })
        await client.configure(failHistory: true)
        store.opened()
        try await settle(store)
        expectNotNil(store.selected)
        expectNil(store.currentError)
        expectNotNil(store.historyError)
        let score = store.selected?.iq
        store.closed()
        let restored = makeStore(client, cache: url, now: { date })
        expectEqual(restored.selected?.iq, score)
        await client.configure(failCurrent: true, failHistory: true)
        date = date.addingTimeInterval(70)
        restored.opened()
        try await settle(restored)
        expectEqual(restored.selected?.iq, score)
        expectNotNil(restored.currentError)
    }

    @MainActor func testSelectionDoesNotFetchAndManualRefreshIsExplicit() async throws {
        let client = StubClient()
        var date = Date()
        let store = makeStore(client, now: { date })
        store.opened()
        try await settle(store)
        expectEqual(store.efforts.count, 6)
        expectEqual(store.bestEffort?.effort, "high")
        expectEqual(store.selected?.effort, "high")
        let choice = try unwrap(store.points.first { $0.model == "gpt-5.6-luna" })
        store.select(choice.id)
        expectEqual(store.selectedID, choice.id)
        var counts = await client.counts()
        expectEqual(counts, [1, 1])
        date = date.addingTimeInterval(4)
        store.refresh(force: true)
        try await settle(store)
        counts = await client.counts()
        expectEqual(counts, [2, 2])
        store.closed()
        date = date.addingTimeInterval(4)
        store.refresh(force: true)
        counts = await client.counts()
        expectEqual(counts, [2, 2])
    }

    func testLiveAPIWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["GPT_IQ_LIVE_TEST"] == "1" else { print("SKIP Live API (set GPT_IQ_LIVE_TEST=1 to enable)"); return }
        let client = RadarClient()
        async let current = client.efficiency()
        async let history = client.history()
        let (result, past) = try await (current, history)
        expectFalse(result.availablePoints.isEmpty)
        expectTrue(past.keys.allSatisfy { !$0.hasPrefix("latest:") && $0.contains("@") })
        expectTrue(result.availablePoints.contains { $0.harnessKind == .claudeCode })
        expectTrue(result.availablePoints.contains { $0.harnessKind == .dsh })
        expectTrue(past.keys.contains { $0.hasPrefix("dsh-") })
        expectTrue(result.gptPoints.contains { !HistoryMath.series(in: past, for: $0).isEmpty })
    }

    func testHarnessMappingAndInsufficientSamples() throws {
        let result: Efficiency = try fixture("efficiency")
        expectEqual(Harness.resolve(model: "deepseek-v4-flash"), .codex)
        expectEqual(Harness.resolve(model: "dsh-deepseek-v4-flash"), .dsh)
        expectEqual(Harness.resolve(model: "kiro-claude-opus-5.5"), .kiro)
        expectEqual(Harness.resolve(model: "claude-opus-5"), .claudeCode)
        expectEqual(Harness.resolve(model: "gpt-future", explicit: "unknown-harness"), .other)
        expectEqual(Harness.resolve(model: "new-model"), .other)
        let empty = try unwrap(result.availablePoints.first { $0.model == "kiro-claude-opus-5.5" })
        expectFalse(empty.hasScore)
        expectFalse(empty.isRankable)
        let sparse = try unwrap(result.availablePoints.first { $0.id == "claude-sonnet-5@high" })
        expectTrue(sparse.hasScore)
        expectFalse(sparse.isRankable)
        let past: History = try fixture("history")
        let dsh = try unwrap(result.availablePoints.first { $0.id == "dsh-deepseek-v4-flash@max" })
        expectFalse(HistoryMath.series(in: past, for: dsh).isEmpty)
    }

    func testHarnessSwitchingIsLocalAndKeepsUnavailableRows() async throws {
        let client = StubClient()
        let store = makeStore(client)
        store.opened()
        try await settle(store)
        expectTrue(store.harnesses.contains(.claudeCode))
        expectTrue(store.harnesses.contains(.dsh))
        expectTrue(store.harnesses.contains(.kiro))
        store.selectHarness(.claudeCode)
        expectTrue(store.efforts.allSatisfy { $0.harnessKind == .claudeCode })
        expectEqual(store.efforts.count, 5)
        expectTrue(store.efforts.contains { !$0.isRankable })
        expectEqual(store.bestEffort?.effort, "low")
        store.selectModel("claude-opus-5")
        let remembered = store.selectedID
        store.selectHarness(.dsh)
        expectTrue(store.efforts.allSatisfy { $0.model.hasPrefix("dsh-") })
        store.selectHarness(.claudeCode)
        expectEqual(store.selectedID, remembered)
        store.selectHarness(.kiro)
        expectEqual(store.efforts.count, 1)
        expectNil(store.bestEffort)
        let counts = await client.counts()
        expectEqual(counts, [1, 1])
        store.closed()
    }

    func testLegacyHistoryCacheRefreshesOnlyAfterOpening() async throws {
        let client = StubClient()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aicy-legacy-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = makeStore(client, cache: url)
        store.opened()
        try await settle(store)
        store.closed()
        var legacy = try unwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        legacy.removeValue(forKey: "version")
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let restored = makeStore(client, cache: url)
        expectNotNil(restored.snapshot)
        var counts = await client.counts()
        expectEqual(counts, [1, 1])
        restored.opened()
        try await settle(restored)
        counts = await client.counts()
        expectEqual(counts, [1, 2])
        restored.closed()
    }
}
