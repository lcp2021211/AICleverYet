import SwiftUI
import Charts
import RadarCore

struct TrendTrigger: View {
    let point: ModelPoint
    let series: [HistoryPoint]
    let loading: Bool
    let error: String?
    let panelOpen: Bool
    @State private var presented = false
    @State private var triggerHovered = false
    @State private var cardHovered = false
    @State private var dismissal: Task<Void, Never>?
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
        .accessibilityLabel("查看 \(point.effortName) IQ 趋势")
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
    @State private var cursor: HistoryPoint?
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { scheme == .dark ? Color(red: 0.52, green: 0.7, blue: 1) : radarBlue }
    private var lower: Double { max(0, (series.map(\.score).min() ?? 0) - 1) }
    private var upper: Double { min(150, (series.map(\.score).max() ?? 149) + 1) }
    private var ticks: [Date] {
        guard let first = series.first?.ts, let last = series.last?.ts else { return [] }
        return (0...4).map { first.addingTimeInterval(last.timeIntervalSince(first) * Double($0) / 4) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(point.displayName).font(.system(size: 12, weight: .semibold))
                    Text("\(point.effortName) · IQ 趋势").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("近 7 天").font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
                    .padding(.horizontal, 9).padding(.vertical, 5).background(accent.opacity(0.09), in: Capsule())
            }
            if series.count >= 2 {
                HStack(spacing: 17) {
                    delta(hours: 24, title: "24h")
                    delta(hours: 168, title: "7d")
                    Spacer()
                }
                plot.frame(height: 155)
                HStack {
                    if let sample = cursor ?? series.last {
                        Text(sample.ts, format: .dateTime.year().month().day().hour().minute())
                        Spacer()
                        Text(String(format: "IQ %.1f", sample.score)).fontWeight(.semibold).foregroundStyle(accent)
                    }
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Text(error == nil ? "移动到曲线上，看看每个时刻的小起伏。" : "历史缓存 · \(error!)")
                    .font(.system(size: 9)).foregroundStyle(error == nil ? Color.secondary : Color.orange)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 26, weight: .light)).foregroundStyle(accent.opacity(0.6))
                    Text(loading ? "历史信号正在抵达…" : error ?? "历史还不够，过些时候再来看看。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 130)
            }
            if !point.isRankable {
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

    private var plot: some View {
        Chart {
            ForEach(series) { sample in
                AreaMark(x: .value("时间", sample.ts), yStart: .value("基线", lower), yEnd: .value("IQ", sample.score))
                    .foregroundStyle(LinearGradient(colors: [accent.opacity(0.2), accent.opacity(0.015)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("时间", sample.ts), y: .value("IQ", sample.score))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)).foregroundStyle(accent)
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
                            Text(date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                            Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
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
        .accessibilityLabel("\(point.effortName) 的历史 IQ，共 \(series.count) 个样本，时间轴包含五个日期和时间刻度")
    }
}
