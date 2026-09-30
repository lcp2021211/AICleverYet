import Foundation

public struct Efficiency: Codable, Sendable {
    public var sourceUpdatedAt: Date?
    public var points: [ModelPoint]

    public var gptPoints: [ModelPoint] {
        points.filter { $0.model.lowercased().hasPrefix("gpt-") && $0.iq?.isFinite == true && ($0.total ?? 0) > 0 }
    }
}

public struct ModelPoint: Codable, Identifiable, Sendable {
    public var model: String
    public var effort: String
    public var iq: Double?
    public var passed: Double?
    public var total: Double?
    public var averagePriceUsd: Double?
    public var priceAggregation: String?
    public var averageMinutes: Double?
    public var sourceUpdatedAt: Date?
    public var id: String { model + "@" + effort }
    public var displayName: String { model.replacingOccurrences(of: "gpt-", with: "GPT-") }
    public var effortName: String { effort.uppercased() }
}

public struct HistoryPoint: Codable, Identifiable, Sendable {
    public var ts: Date
    public var score: Double
    public var n: Int?
    public var id: Date { ts }

    public init(ts: Date, score: Double, n: Int? = nil) {
        self.ts = ts
        self.score = score
        self.n = n
    }

    private enum CodingKeys: String, CodingKey { case ts, score, n }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ts = try values.decode(Date.self, forKey: .ts)
        // The public endpoint also contains series with ungraded (null) scores.
        // Preserve decoding of the rest of the payload; invalid samples are filtered.
        score = try values.decodeIfPresent(Double.self, forKey: .score) ?? -1
        n = try values.decodeIfPresent(Int.self, forKey: .n)
    }
}

public typealias History = [String: [HistoryPoint]]

public struct ScoreChange {
    public let value: Double
    public let approximate: Bool
}

public enum HistoryMath {
    // Never substitute aggregate or latest: series for the selected effort.
    public static func series(in history: History, for point: ModelPoint) -> [HistoryPoint] {
        let valid = (history[point.id] ?? []).filter { $0.score.isFinite && (0...150).contains($0.score) && ($0.n ?? 0) > 0 }
        let unique = Dictionary(valid.map { ($0.ts, $0) }, uniquingKeysWith: { _, last in last })
        let sorted = unique.values.sorted { $0.ts < $1.ts }
        guard let end = sorted.last?.ts else { return [] }
        return sorted.filter { $0.ts >= end.addingTimeInterval(-7 * 86400 - 3600) }
    }

    // Compare history to history: its rounding and timestamp differ from live IQ.
    public static func change(_ series: [HistoryPoint], hours: Double) -> ScoreChange? {
        guard let last = series.last, series.count > 1 else { return nil }
        let target = last.ts.addingTimeInterval(-hours * 3600)
        guard let baseline = series.dropLast().min(by: {
            abs($0.ts.timeIntervalSince(target)) < abs($1.ts.timeIntervalSince(target))
        }), abs(baseline.ts.timeIntervalSince(target)) <= 3900 else { return nil }
        return ScoreChange(value: last.score - baseline.score,
                           approximate: abs(baseline.ts.timeIntervalSince(target)) > 900)
    }
}

public enum RadarJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = formatter.date(from: text) { return date }
            if let date = fractional.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
        }
        return decoder
    }
}
