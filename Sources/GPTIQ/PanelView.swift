import SwiftUI
import Charts
import RadarCore

private let mint = Color(red: 0.10, green: 0.65, blue: 0.52)

struct PanelView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.colorScheme) private var scheme
    var quit: () -> Void

    private var card: Color { scheme == .dark ? Color.white.opacity(0.045) : .white.opacity(0.72) }

    var body: some View {
        VStack(spacing: 12) {
            header
            if let point = store.selected {
                modelSelector(point)
                comparisonCard
                historyCard
                sourceInfo(point)
            } else {
                emptyState
            }
            footer
        }
        .padding(16)
        .frame(width: 400)
        .background {
            ZStack(alignment: .topLeading) {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(colors: [mint.opacity(scheme == .dark ? 0.13 : 0.09), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 330)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.path")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(mint)
                .frame(width: 33, height: 33)
                .background(mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text("GPT IQ").font(.system(size: 15, weight: .bold, design: .rounded))
                Text("INTELLIGENCE, AT A GLANCE").font(.system(size: 8, weight: .medium)).tracking(1.3).foregroundStyle(.secondary)
            }
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.75).frame(width: 25, height: 25)
                    .accessibilityLabel("正在刷新")
            } else {
                Button { store.refresh(force: true) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium))
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("刷新 IQ 和历史数据").accessibilityLabel("刷新数据")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private func modelSelector(_ point: ModelPoint) -> some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(store.models, id: \.self) { model in
                    Button { store.selectModel(model) } label: {
                        if point.model == model { Label(model, systemImage: "checkmark") }
                        else { Text(model) }
                    }
                }
            } label: {
                Text(point.displayName).font(.system(size: 14, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("选择 GPT 模型")
            Spacer(minLength: 0)
            Text("\(store.efforts.count) 个推理档位")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(card, in: RoundedRectangle(cornerRadius: 10))
    }

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "crown.fill").font(.system(size: 11)).foregroundStyle(mint)
                Text("最高 IQ").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(store.bestEffort?.iq.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer()
                Text(store.bestEffort?.effortName ?? "")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(mint).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(mint.opacity(0.1), in: Capsule())
            }
            HStack(spacing: 0) {
                Text("推理强度").frame(width: 76, alignment: .leading)
                Text("IQ").frame(maxWidth: .infinity, alignment: .trailing)
                Text("耗时 / 分").frame(width: 70, alignment: .trailing)
                Text("成本 / $").frame(width: 66, alignment: .trailing)
            }
            .font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 9)
            VStack(spacing: 2) {
                ForEach(store.efforts) { point in
                    effortRow(point)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "pin.fill").font(.system(size: 8))
                Text("点击档位，切换菜单栏 IQ 与下方趋势")
                Spacer(minLength: 0)
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(mint.opacity(0.13), lineWidth: 1))
    }

    private func effortRow(_ point: ModelPoint) -> some View {
        let selected = point.id == store.selectedID
        let best = point.iq == store.bestEffort?.iq
        return Button { store.select(point.id) } label: {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(selected ? mint : .clear).frame(width: 4, height: 4)
                    Text(point.effortName).font(.system(size: 10, weight: selected ? .bold : .medium, design: .monospaced))
                }.frame(width: 76, alignment: .leading)
                HStack(spacing: 4) {
                    if best { Image(systemName: "crown.fill").font(.system(size: 8)) }
                    Text(point.iq.map { String(format: "%.2f", $0) } ?? "—")
                        .font(.system(size: 16, weight: best ? .bold : .medium, design: .rounded)).monospacedDigit()
                }.foregroundStyle(best ? mint : Color.primary).frame(maxWidth: .infinity, alignment: .trailing)
                Text(point.averageMinutes.map { String(format: "%.1f", $0) } ?? "—")
                    .frame(width: 70, alignment: .trailing)
                Text(point.averagePriceUsd.map { String(format: "%.2f", $0) } ?? "—")
                    .frame(width: 66, alignment: .trailing)
            }
            .font(.system(size: 11, design: .rounded)).monospacedDigit()
            .padding(.horizontal, 9).frame(height: 29)
            .background(selected ? mint.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(point.displayName) · \(point.effortName) · \(Int(point.total ?? 0)) 个样本；点击固定到菜单栏")
        .accessibilityLabel("\(point.effortName)，IQ \(point.iq ?? 0)\(best ? "，最高分" : "")\(selected ? "，已固定" : "")")
    }

    private var historyCard: some View {
        let series = store.series
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(store.selected?.effortName ?? "") · IQ 趋势").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("近 7 天").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            if series.count >= 2 {
                HStack(spacing: 20) {
                    changeLabel(HistoryMath.change(series, hours: 24), title: "24h")
                    changeLabel(HistoryMath.change(series, hours: 168), title: "7d")
                    Spacer()
                }
                Sparkline(series: series).frame(height: 60)
                HStack {
                    Text(series.first!.ts, format: .dateTime.month().day())
                    Spacer()
                    Text(series.last!.ts, format: .dateTime.month().day().hour().minute())
                }.font(.system(size: 9)).foregroundStyle(.tertiary)
                if let error = store.historyError {
                    Text("历史缓存 · \(error)").font(.system(size: 9)).foregroundStyle(.orange)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 24, weight: .light)).foregroundStyle(mint.opacity(0.6))
                    Text(store.isLoading ? "正在读取历史…" : store.historyError ?? "这个档位暂无足够历史")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 122)
            }
        }.padding(15).background(card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func changeLabel(_ change: ScoreChange?, title: String) -> some View {
        HStack(spacing: 5) {
            Text((change?.approximate == true ? "≈ " : "") + title)
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if let change {
                Text(String(format: "%+.1f", abs(change.value) < 0.05 ? 0 : change.value))
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(change.value < -0.05 ? Color.orange : change.value > 0.05 ? mint : Color.secondary)
            } else {
                Text("样本不足").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }.help("历史序列末值减去对应时间的历史值；≈ 表示采用相差一小时左右的最近样本")
    }

    private func sourceInfo(_ point: ModelPoint) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let error = store.currentError {
                Label(error, systemImage: "wifi.slash").font(.system(size: 10)).foregroundStyle(.orange)
            }
            HStack {
                Text("获取于")
                if let date = store.currentFetchedAt { Text(date, format: .dateTime.month().day().hour().minute()) }
                Spacer()
                Text("仅打开时更新").foregroundStyle(mint)
            }
            HStack {
                Text("该档位评测更新")
                if let date = point.sourceUpdatedAt { Text(date, format: .dateTime.month().day().hour().minute()) }
                else { Text("时间未知") }
                Spacer()
            }
            Text("成本为 USD 中位数 / 评测；IQ 来自 Codex Radar。")
                .foregroundStyle(.tertiary)
        }.font(.system(size: 9)).foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            Image(systemName: store.currentError == nil ? "waveform.path" : "wifi.slash")
                .font(.system(size: 39, weight: .ultraLight)).foregroundStyle(mint)
            Text(store.currentError ?? "正在获取 GPT 的 IQ…").font(.system(size: 14, weight: .medium))
            Text("无需登录，只在你打开时连接 Codex Radar。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if store.currentError != nil {
                Button("重新获取") { store.refresh(force: true) }.buttonStyle(.borderedProminent).tint(mint)
            }
        }.frame(maxWidth: .infinity).frame(height: 265)
    }

    private var footer: some View {
        VStack(spacing: 11) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
            HStack {
                Link(destination: URL(string: "https://codexradar.com")!) {
                    HStack(spacing: 4) {
                        Text("Codex Radar")
                        Image(systemName: "arrow.up.right").font(.system(size: 8))
                    }
                }.foregroundStyle(.secondary)
                Spacer()
                Button(action: quit) { Image(systemName: "power").font(.system(size: 11)).frame(width: 20, height: 16) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("退出 GPT IQ")
                    .accessibilityLabel("退出 GPT IQ").keyboardShortcut("q", modifiers: .command)
            }.font(.system(size: 10))
        }
    }
}

private struct Sparkline: View {
    let series: [HistoryPoint]
    private var lower: Double { max(0, (series.map(\.score).min() ?? 0) - 0.6) }
    private var upper: Double { (series.map(\.score).max() ?? 1) + 0.6 }
    var body: some View {
        Chart(series) { point in
            AreaMark(x: .value("时间", point.ts), yStart: .value("基线", lower), yEnd: .value("IQ", point.score))
                .foregroundStyle(LinearGradient(colors: [mint.opacity(0.18), mint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("时间", point.ts), y: .value("IQ", point.score))
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)).foregroundStyle(mint)
            if point.id == series.last?.id {
                PointMark(x: .value("时间", point.ts), y: .value("IQ", point.score))
                    .symbolSize(22).foregroundStyle(mint)
            }
        }
        .chartYScale(domain: lower...upper)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel().font(.system(size: 8)).foregroundStyle(Color.secondary)
            }
        }
        .accessibilityLabel("近七天 IQ 趋势，共 \(series.count) 个历史样本")
    }
}
