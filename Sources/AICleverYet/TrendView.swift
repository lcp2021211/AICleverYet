import SwiftUI
import Charts
import RadarCore

// Disambiguate the legacy property wrapper from the SDK's newer State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct TrendTrigger: View {
    let point: ModelPoint
    let series: [HistoryPoint]
    let loading: Bool
    let error: String?
    let panelOpen: Bool
    @ViewState<Bool> private var presented = false
    @ViewState<Bool> private var triggerHovered = false
    @ViewState<Bool> private var cardHovered = false
    @ViewState<Task<Void, Never>?> private var dismissal: Task<Void, Never>?
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { scheme == .dark ? Color(red: 0.52, green: 0.7, blue: 1) : radarBlue }

    var body: some View {
        Button { if panelOpen { presented.toggle() } } label: {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accent.opacity(series.isEmpty ? 0.45 : 0.85))
                .frame(width: 27, height: 29)
                .background(accent.opacity(presented ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查看 \(point.effortName) \(point.scoreLabel)趋势")
        .onHover { inside in
            triggerHovered = inside
            if inside && panelOpen { dismissal?.cancel(); presented = true }
            else { scheduleDismissal() }
        }
        .popover(isPresented: $presented, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            TrendCard(point: point, series: series, loading: loading, error: error)
                .onHover { inside in
                    cardHovered = inside
                    if inside { dismissal?.cancel() } else { scheduleDismissal() }
                }
        }
        .onDisappear { dismissal?.cancel(); presented = false }
        .onChange(of: panelOpen) { open in
            if !open { dismissal?.cancel(); presented = false; triggerHovered = false; cardHovered = false }
        }
    }

    private func scheduleDismissal() {
        dismissal?.cancel()
        // Leave enough time to cross the native popover arrow into the chart.
        dismissal = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 450_000_000) } catch { return }
            if !triggerHovered && !cardHovered { presented = false }
        }
    }
}

struct TrendCard: View {
    let point: ModelPoint
    let series: [HistoryPoint]
    var loading = false
    var error: String?
    @ViewState<HistoryPoint?> private var cursor: HistoryPoint?
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { scheme == .dark ? Color(red: 0.52, green: 0.7, blue: 1) : radarBlue }
    private var lower: Double { max(0, (series.map(\.score).min() ?? 0) - 1) }
    private var upper: Double { min(150, (series.map(\.score).max() ?? 149) + 1) }
    private var ticks: [Date] {
        guard let first = series.first?.ts, let last = series.last?.ts else { return [] }
        if point.isBench {
            let count = min(5, series.count)
            return (0..<count).map { series[count == 1 ? 0 : $0 * (series.count - 1) / (count - 1)].ts }
        }
        return (0...4).map { first.addingTimeInterval(last.timeIntervalSince(first) * Double($0) / 4) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(point.displayName).font(.system(size: 12, weight: .semibold))
                    Text("\(point.effortName) · \(point.scoreLabel)趋势").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("近 7 天").font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
                    .padding(.horizontal, 9).padding(.vertical, 5).background(accent.opacity(0.09), in: Capsule())
            }
            if !series.isEmpty {
                HStack(spacing: 17) {
                    delta(hours: 24, title: point.isBench ? "1d" : "24h")
                    delta(hours: 168, title: "7d")
                    Spacer()
                }
                plot.frame(height: 155)
                HStack {
                    if let sample = cursor ?? series.last {
                        if point.isBench { Text(utcDay(sample.ts) + " UTC · \(sample.n ?? 0)/64 题") }
                        else { Text(sample.ts, format: .dateTime.year().month().day().hour().minute()) }
                        Spacer()
                        Text(String(format: "\(point.scoreLabel) %.1f", sample.score)).fontWeight(.semibold).foregroundStyle(accent)
                    }
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Text(error == nil ? (point.isBench ? "UTC 每日最后成绩；无判分日留空，非小时趋势。" : "移动到曲线上，看看每个时刻的小起伏。") : "历史缓存 · \(error!)")
                    .font(.system(size: 9)).foregroundStyle(error == nil ? Color.secondary : Color.orange)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 26, weight: .light)).foregroundStyle(accent.opacity(0.6))
                    Text(loading ? "历史信号正在抵达…" : error ?? "历史还不够，过些时候再来看看。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 130)
            }
            if !point.isRankable || point.isBench {
                Text(point.qualityNote).font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20).frame(width: 410)
        .background(scheme == .dark ? Color(red: 0.06, green: 0.085, blue: 0.15) : Color(red: 0.975, green: 0.984, blue: 1))
    }

    private func delta(hours: Double, title: String) -> some View {
        let change = HistoryMath.change(series, hours: hours)
        return HStack(spacing: 5) {
            Text((change?.approximate == true ? "≈ " : "") + title).foregroundStyle(.secondary)
            Text(change.map { String(format: "%+.1f", abs($0.value) < 0.05 ? 0 : $0.value) } ?? "样本不足")
                .fontWeight(.semibold).foregroundStyle((change?.value ?? 0) < -0.05 ? Color.orange : accent)
        }.font(.system(size: 11, design: .rounded)).monospacedDigit()
    }

    private func utcDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func segment(_ sample: HistoryPoint) -> Int {
        var group = 0
        for i in series.indices where i > 0 && series[i].ts <= sample.ts {
            if series[i].ts.timeIntervalSince(series[i - 1].ts) > 86400 { group += 1 }
        }
        return group
    }

    private var plot: some View {
        Chart {
            ForEach(series) { sample in
                if point.isBench {
                    PointMark(x: .value("日期", sample.ts), y: .value("雷达分", sample.score))
                        .symbolSize(24).foregroundStyle(accent)
                    LineMark(x: .value("日期", sample.ts), y: .value("雷达分", sample.score), series: .value("连续日期", segment(sample)))
                        .lineStyle(StrokeStyle(lineWidth: 2)).foregroundStyle(accent)
                } else {
                    AreaMark(x: .value("时间", sample.ts), yStart: .value("基线", lower), yEnd: .value("IQ", sample.score))
                        .foregroundStyle(accent.opacity(0.1))
                    LineMark(x: .value("时间", sample.ts), y: .value("IQ", sample.score)).foregroundStyle(accent)
                }
            }
            if let cursor {
                RuleMark(x: .value("时间", cursor.ts)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(accent.opacity(0.45))
                PointMark(x: .value("时间", cursor.ts), y: .value("IQ", cursor.score)).symbolSize(35).foregroundStyle(accent)
            }
        }
        .chartYScale(domain: lower...max(lower + 0.1, upper))
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.04))
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : value.index == ticks.count - 1 ? .topTrailing : .top,
                               collisionResolution: .disabled) {
                    if let date = value.as(Date.self) {
                        VStack(spacing: 2) {
                            if point.isBench { Text(utcDay(date).dropFirst(5)); Text("UTC") }
                            else {
                            Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                            Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        }
                        }.font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Color.primary.opacity(0.07))
                AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.secondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let frame = geometry[proxy.plotAreaFrame]
                            guard frame.contains(location), let date: Date = proxy.value(atX: location.x - frame.minX) else { cursor = nil; return }
                            cursor = series.min { abs($0.ts.timeIntervalSince(date)) < abs($1.ts.timeIntervalSince(date)) }
                        case .ended: cursor = nil
                        }
                    }
            }
        }
        .accessibilityLabel("\(point.effortName) 的历史\(point.scoreLabel)，共 \(series.count) 个样本，时间轴标明采样日期")
    }
}
