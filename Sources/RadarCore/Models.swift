import Foundation

public struct Efficiency: Codable, Sendable {
    public var sourceUpdatedAt: Date?
    public var points: [ModelPoint]

    // Keep ungraded rows: hiding them would make an available harness disappear.
    public var availablePoints: [ModelPoint] {
        points.filter { !$0.model.isEmpty && !$0.effort.isEmpty }
    }

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
    public var harness: String?
    public var id: String { model + "@" + effort }
    public var harnessKind: Harness { Harness.resolve(model: model, explicit: harness) }
    public var displayName: String {
        var label = model
        for prefix in ["dsh-", "kiro-"] where label.hasPrefix(prefix) { label = String(label.dropFirst(prefix.count)) }
        return label.replacingOccurrences(of: "gpt-", with: "GPT-")
            .replacingOccurrences(of: "claude-", with: "Claude ")
            .replacingOccurrences(of: "deepseek-", with: "DeepSeek ")
            .replacingOccurrences(of: "gemini-", with: "Gemini ")
            .replacingOccurrences(of: "glm-", with: "GLM-")
            .replacingOccurrences(of: "grok-", with: "Grok ")
            .replacingOccurrences(of: "kimi-", with: "Kimi ")
    }
    public var effortName: String { effort.uppercased() }
    public var hasScore: Bool { iq.map { $0.isFinite && (0...150).contains($0) } == true && (total ?? 0) > 0 }
    // A local comparison guard, not a claim of statistical significance or an API flag.
    public static let minimumSamples: Double = 30
    public var isRankable: Bool { hasScore && (total ?? 0) >= Self.minimumSamples }
    public var qualityNote: String {
        if !hasScore { return "尚无有效评分；等待更多评测。" }
        if !isRankable { return "仅 \(Int(total ?? 0)) 份样本；本 App 以至少 30 份样本作为参与最高分比较的门槛。原始 IQ：\(String(format: "%.2f", iq!))。" }
        return "\(Int(total ?? 0)) 份评测样本。IQ 为 Codex Radar 评测分数。"
    }
}

public enum Harness: String, CaseIterable, Identifiable, Sendable {
    case codex, claudeCode, dsh, kimiCode, zcode, grok, antigravity, codebuddy, kiro, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .dsh: return "DSH"
        case .kimiCode: return "Kimi Code"
        case .zcode: return "ZCode"
        case .grok: return "Grok"
        case .antigravity: return "Antigravity"
        case .codebuddy: return "CodeBuddy"
        case .kiro: return "Kiro"
        case .other: return "其他"
        }
    }
    public var symbol: String {
        switch self {
        case .codex: return "terminal"
        case .claudeCode: return "asterisk"
        case .dsh: return "water.waves"
        case .kimiCode: return "moon.stars"
        case .zcode: return "bolt"
        case .grok: return "sparkle"
        case .antigravity: return "paperplane"
        case .codebuddy: return "person.2"
        case .kiro: return "cube.transparent"
        case .other: return "square.grid.2x2"
        }
    }
    public static func resolve(model: String, explicit: String? = nil) -> Harness {
        if let explicit, !explicit.isEmpty {
            let known: [String: Harness] = ["codex": .codex, "claude-code": .claudeCode,
                "dsh": .dsh, "kimi-code": .kimiCode, "zcode": .zcode, "grok": .grok,
                "grok-build": .grok, "antigravity": .antigravity, "codebuddy": .codebuddy, "kiro": .kiro]
            return known[explicit.lowercased()] ?? .other
        }
        // API v3 has no harness field. These model mappings follow deng.codexradar.com.
        if model.hasPrefix("kiro-") { return .kiro }
        if model.hasPrefix("dsh-") { return .dsh }
        if model.hasPrefix("claude-") { return .claudeCode }
        if model.hasPrefix("gpt-") || model.hasPrefix("deepseek-") { return .codex }
        if model == "k3" || model.hasPrefix("kimi-") { return .kimiCode }
        if model.hasPrefix("glm-") { return .zcode }
        if model.hasPrefix("grok-") { return .grok }
        if model.hasPrefix("gemini-") { return .antigravity }
        if model == "hy4-preview" { return .codebuddy }
        return .other
    }
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
