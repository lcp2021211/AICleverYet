import Foundation

public protocol BenchFetching: RadarFetching {
    func bench(model: String?) async throws -> BenchBatch
}

public struct BenchBatch: Sendable {
    public let catalog: Efficiency
    public let model: String
    public let points: [ModelPoint]
    public let history: History
    public let failures: [String: String]
    public init(catalog: Efficiency, model: String, points: [ModelPoint], history: History, failures: [String: String]) {
        self.catalog = catalog; self.model = model; self.points = points; self.history = history; self.failures = failures
    }
}

struct BenchSelection: Codable, Hashable, Sendable {
    let model: String
    let effort: String
    var id: String { model + "@" + effort }
}

struct BenchBinding: Decodable, Sendable {
    let enabled: Bool
    let productionReadVerified: Bool
    let benchmark: String
    let catalogVersion: String
    let taskSetSha256: String
    let totalTasks: Int
    let modelEfforts: [BenchSelection]
    let activeDisplaySelection: BenchSelection
    var basis: String { [benchmark, catalogVersion, taskSetSha256].joined(separator: ":") }
    func validate() throws {
        guard enabled, productionReadVerified, totalTasks == 64,
              !modelEfforts.isEmpty, modelEfforts.count <= 100,
              Set(modelEfforts).count == modelEfforts.count,
              modelEfforts.contains(activeDisplaySelection),
              modelEfforts.allSatisfy({ $0.model.hasPrefix("gpt-") && !$0.effort.isEmpty }),
              !benchmark.isEmpty, !catalogVersion.isEmpty, taskSetSha256.count == 64 else { throw RadarError.invalid }
    }
    var catalog: Efficiency {
        Efficiency(points: modelEfforts.map {
            ModelPoint(model: $0.model, effort: $0.effort, harness: "codex", scoreVersion: "radar-bench-v2-150", requiredTasks: totalTasks)
        }, basis: basis)
    }
}

struct BenchSummary: Decodable, Sendable {
    let schema: String
    let benchmark: String
    let scoreVersion: String
    let scoreMax: Double
    let catalogVersion: String
    let taskSetSha256: String
    let model: String
    let effort: String
    let score: Double?
    let coverage: Int
    let requiredTasks: Int
    let scoreStatus: String
    let scoringPolicyVersion: String
    let gradedRunsCount: Int
    let statistics: Statistics?
    let statisticsState: String?
    let history: DailyHistory?
    let historyState: String?

    struct Statistics: Decodable, Sendable {
        let sampleCount: Int
        let costBasis: String
        let metrics: Metrics
        struct Metrics: Decodable, Sendable {
            let elapsedMs: Metric?
            let apiEquivalentUsd: Metric?
        }
    }
    struct Metric: Decodable, Sendable {
        let knownTotal: Double?
        let knownSamples: Int
        let missingSamples: Int
        var mean: Double? {
            guard knownSamples > 0, missingSamples >= 0, let knownTotal,
                  knownTotal.isFinite, knownTotal >= 0 else { return nil }
            return knownTotal / Double(knownSamples)
        }
    }
    struct DailyHistory: Decodable, Sendable {
        let schema: String
        let scoreVersion: String
        let scoreMax: Double
        let model: String
        let effort: String
        let timeZone: String
        let bucket: String
        let points: [Point]
        struct Point: Decodable, Sendable {
            let at: Date
            let score: Double
            let coverage: Int
            let requiredTasks: Int
        }
    }

    func project(binding: BenchBinding, selection: BenchSelection) throws -> (ModelPoint, [HistoryPoint]) {
        guard schema == "radar-bench-public-summary-v5-150-daily-graded-count",
              benchmark == binding.benchmark, catalogVersion == binding.catalogVersion,
              taskSetSha256 == binding.taskSetSha256, model == selection.model, effort == selection.effort,
              scoreVersion == "radar-bench-v2-150", scoreMax == 150,
              scoringPolicyVersion == "radar-bench-v2-last3-per-task-equal-weight-150",
              requiredTasks == binding.totalTasks, (0...requiredTasks).contains(coverage), gradedRunsCount >= coverage,
              score.map({ $0.isFinite && (0...150).contains($0) }) ?? (coverage == 0),
              (coverage == 0 ? score == nil : score != nil),
              scoreStatus == (coverage == 0 ? "missing_current_result" : coverage == requiredTasks ? "complete" : "provisional")
        else { throw RadarError.invalid }
        var past: [HistoryPoint] = []
        if historyState == "available", let history {
            guard history.schema == "radar-bench-public-history-v1-150-daily",
                  history.scoreVersion == scoreVersion, history.scoreMax == 150,
                  history.model == model, history.effort == effort,
                  history.timeZone == "UTC", history.bucket == "day" else { throw RadarError.invalid }
            var previous = Date.distantPast
            for row in history.points {
                guard row.at > previous, row.at.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) == 0,
                      row.score.isFinite, (0...150).contains(row.score),
                      row.requiredTasks == requiredTasks, (1...requiredTasks).contains(row.coverage) else { throw RadarError.invalid }
                past.append(HistoryPoint(ts: row.at, score: row.score, n: row.coverage))
                previous = row.at
            }
        }
        let stats = statisticsState == "available" ? statistics : nil
        let time = stats?.metrics.elapsedMs
        let cost = stats?.costBasis.hasPrefix("official_standard_api_equivalent") == true ? stats?.metrics.apiEquivalentUsd : nil
        let note = "耗时与 API 等价成本为已知样本均值，非订阅实扣。耗时样本 \(time?.knownSamples ?? 0)/\(stats?.sampleCount ?? 0)，成本样本 \(cost?.knownSamples ?? 0)/\(stats?.sampleCount ?? 0)。"
        let point = ModelPoint(model: model, effort: effort, iq: score, total: Double(gradedRunsCount),
                               averagePriceUsd: cost?.mean, priceAggregation: "mean", averageMinutes: time?.mean.map { $0 / 60000 },
                               harness: "codex", scoreVersion: scoreVersion, coverage: coverage, requiredTasks: requiredTasks, metricsNote: note)
        return (point, past)
    }
}
