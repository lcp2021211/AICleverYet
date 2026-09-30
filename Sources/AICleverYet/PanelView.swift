import SwiftUI
import RadarCore

let radarBlue = Color(red: 0.23, green: 0.43, blue: 0.96)

struct PanelView: View {
    @ObservedObject var store: RadarStore
    @Environment(\.colorScheme) private var scheme
    var quit: () -> Void
    private var ink: Color { scheme == .dark ? Color(red: 0.84, green: 0.9, blue: 1) : Color(red: 0.12, green: 0.19, blue: 0.34) }
    private var accent: Color { scheme == .dark ? Color(red: 0.48, green: 0.67, blue: 1) : radarBlue }

    var body: some View {
        VStack(spacing: 20) {
            header
            if let point = store.selected {
                harnessPicker
                comparison(point)
            } else { emptyState }
            if let error = store.currentError {
                Label(store.snapshot == nil ? error : "离线快照 · \(error)", systemImage: "wifi.slash")
                    .font(.system(size: 10)).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(22)
        .frame(width: 460)
        .foregroundStyle(ink)
        .background {
            ZStack(alignment: .topTrailing) {
                (scheme == .dark ? Color(red: 0.045, green: 0.065, blue: 0.12) : Color(red: 0.955, green: 0.968, blue: 0.992))
                RadialGradient(colors: [radarBlue.opacity(scheme == .dark ? 0.23 : 0.12), .clear], center: .topTrailing, startRadius: 0, endRadius: 330)
                Circle().stroke(accent.opacity(0.045), lineWidth: 24).frame(width: 245, height: 245).offset(x: 105, y: -160)
            }
        }
        .tint(accent)
    }

    private var header: some View {
        HStack(spacing: 11) {
            CleverMark().frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("AICleverYet").font(.system(size: 22, weight: .bold, design: .rounded)).tracking(-0.6)
                Text("今天，谁更聪明一点？").font(.system(size: 10, weight: .medium)).foregroundStyle(ink.opacity(0.55))
            }
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small).frame(width: 32, height: 32).accessibilityLabel("正在刷新")
            } else {
                Button { store.refresh(force: true) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .background(accent.opacity(0.07), in: Circle())
                .foregroundStyle(accent).help("刷新数据 · ⌘R").accessibilityLabel("刷新数据")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private var harnessPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("PICK YOUR HARNESS").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.6).foregroundStyle(ink.opacity(0.4))
                Spacer()
                Menu {
                    ForEach(store.harnesses) { h in
                        Button(h.title) { store.selectHarness(h) }
                    }
                } label: {
                    Text("全部 \(store.harnesses.count)").font(.system(size: 9, weight: .medium))
                }.menuStyle(.borderlessButton).fixedSize().foregroundStyle(ink.opacity(0.55))
                harnessArrow(-1)
                harnessArrow(1)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(store.harnesses) { h in harnessCard(h).id(h.id) }
                    }.padding(2)
                }
                .onChange(of: store.selectedHarness) { h in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(h.id, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(store.selectedHarness.id, anchor: .center) }
            }
            .frame(height: 74)
        }
    }

    private func harnessArrow(_ direction: Int) -> some View {
        let index = store.harnesses.firstIndex(of: store.selectedHarness) ?? 0
        let next = index + direction
        return Button {
            guard store.harnesses.indices.contains(next) else { return }
            store.selectHarness(store.harnesses[next])
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18)
        }.buttonStyle(.plain).disabled(!store.harnesses.indices.contains(next))
            .accessibilityLabel(direction < 0 ? "上一个 harness" : "下一个 harness")
    }

    private func harnessCard(_ harness: Harness) -> some View {
        let active = store.selectedHarness == harness
        return Button { store.selectHarness(harness) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: harness.symbol).font(.system(size: 16, weight: .medium))
                    Spacer()
                    if active { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)) }
                    else { Text(String(format: "%02d", store.models(in: harness).count)).font(.system(size: 9, weight: .medium, design: .monospaced)).opacity(0.5) }
                }
                Text(harness.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(active ? .white : ink.opacity(0.7))
            .padding(12).frame(width: 130, height: 70)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [Color(red: 0.30, green: 0.52, blue: 1), Color(red: 0.17, green: 0.31, blue: 0.81)], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    RoundedRectangle(cornerRadius: 15).fill(scheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.8))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(active ? Color.white.opacity(0.18) : accent.opacity(0.07), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(harness.title)，\(store.models(in: harness).count) 个模型\(active ? "，已选择" : "")")
    }

    private func comparison(_ point: ModelPoint) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("THE LINEUP").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(accent.opacity(0.75))
                    Menu {
                        ForEach(store.models, id: \.self) { model in
                            Button {
                                store.selectModel(model)
                            } label: {
                                let label = store.points.first(where: { $0.model == model })?.displayName ?? model
                                if model == point.model { Label(label, systemImage: "checkmark") }
                                else { Text(label) }
                            }
                        }
                    } label: {
                        Text(point.displayName).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1).truncationMode(.middle)
                    }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true).accessibilityLabel("选择模型")
                }
                Spacer(minLength: 8)
                Image(systemName: "sparkles").font(.system(size: 23, weight: .ultraLight)).foregroundStyle(accent.opacity(0.7)).rotationEffect(.degrees(-10))
            }
            HStack(spacing: 0) {
                Text("推理强度").frame(maxWidth: .infinity, alignment: .leading)
                Text("IQ").frame(width: 103, alignment: .trailing)
                Text("耗时 / 分").frame(width: 65, alignment: .trailing)
                Text("成本 / $").frame(width: 60, alignment: .trailing)
                Text("趋势").frame(width: 38, alignment: .trailing)
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(ink.opacity(0.4)).padding(.horizontal, 12)
            ScrollView(.vertical, showsIndicators: store.efforts.count > 6) {
                VStack(spacing: 5) {
                    ForEach(store.efforts) { option in
                        EffortRow(point: option, best: option.isRankable && option.iq == store.bestEffort?.iq,
                                  series: HistoryMath.series(in: store.history, for: option),
                                  loading: store.isLoading, historyError: store.historyError, panelOpen: store.isOpen)
                    }
                }
            }.frame(height: CGFloat(min(store.efforts.count, 6)) * 49 - 5)
            HStack(spacing: 5) {
                Image(systemName: store.bestEffort == nil ? "hourglass" : "sparkle").foregroundStyle(accent)
                Text(store.bestEffort == nil ? "样本还在路上，先让评测再跑一会儿。" : "更用力，不一定更聪明。蓝色标出本组最高分。")
            }.font(.system(size: 9)).foregroundStyle(ink.opacity(0.5))
                .help("最高分比较仅包含至少 30 份样本的档位；这是本 App 的比较门槛。成本为数据源给出的每次评测参考成本。")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            CleverMark().frame(width: 65, height: 65)
            Text(store.currentError == nil ? "聪明的信号，马上就来。" : "信号暂时迷路了。")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(store.currentError == nil ? "正在读取各个 harness 的评测…" : "点右上角刷新，再试一次。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).frame(height: 240)
    }

    private var footer: some View {
        HStack {
            Link(destination: URL(string: "https://codexradar.com")!) {
                HStack(spacing: 5) {
                    Circle().fill(accent.opacity(0.6)).frame(width: 4, height: 4)
                    Text("Codex Radar")
                    Image(systemName: "arrow.up.right").font(.system(size: 8))
                }
            }.foregroundStyle(ink.opacity(0.48))
            Spacer()
            Button("退出", action: quit).buttonStyle(.plain).foregroundStyle(ink.opacity(0.6))
                .keyboardShortcut("q", modifiers: .command)
        }.font(.system(size: 10, weight: .medium))
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(accent.opacity(0.08)).frame(height: 1) }
    }
}

struct CleverMark: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.32).fill(LinearGradient(colors: [Color(red: 0.40, green: 0.64, blue: 1), radarBlue], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: w * 0.2).stroke(.white.opacity(0.2), lineWidth: 1).padding(w * 0.12)
                HStack(spacing: w * 0.12) {
                    Capsule().fill(.white).frame(width: w * 0.075, height: w * 0.23)
                    Capsule().fill(.white).frame(width: w * 0.075, height: w * 0.17).offset(y: -w * 0.035)
                }.rotationEffect(.degrees(-8))
                Circle().fill(.white.opacity(0.9)).frame(width: w * 0.07).offset(x: w * 0.31, y: -w * 0.31)
            }
        }.accessibilityHidden(true)
    }
}

private struct EffortRow: View {
    let point: ModelPoint
    let best: Bool
    let series: [HistoryPoint]
    let loading: Bool
    let historyError: String?
    let panelOpen: Bool
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { scheme == .dark ? Color(red: 0.52, green: 0.7, blue: 1) : radarBlue }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2).fill(best ? accent : accent.opacity(0.15)).frame(width: 3, height: 19)
                VStack(alignment: .leading, spacing: 2) {
                    Text(point.effortName).font(.system(size: 11, weight: best ? .bold : .medium, design: .monospaced))
                    if best { Text("本组最高").font(.system(size: 8, weight: .semibold)) }
                }
            }.foregroundStyle(best ? accent : Color.primary.opacity(0.75)).frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if point.isRankable {
                    Text(String(format: "%.2f", point.iq!))
                        .font(.system(size: 22, weight: best ? .bold : .medium, design: .rounded)).tracking(-0.6)
                        .foregroundStyle(best ? accent : Color.primary.opacity(0.8))
                } else {
                    Text("数据不足").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
            }.frame(width: 103, alignment: .trailing).help(point.qualityNote)
            Text(point.averageMinutes.map { String(format: "%.1f", $0) } ?? "—").frame(width: 65, alignment: .trailing)
            Text(point.averagePriceUsd.map { String(format: "%.2f", $0) } ?? "—").frame(width: 60, alignment: .trailing)
            TrendTrigger(point: point, series: series, loading: loading, error: historyError, panelOpen: panelOpen)
                .frame(width: 38, alignment: .trailing)
        }
        .font(.system(size: 11, design: .rounded)).monospacedDigit()
        .padding(.horizontal, 12).frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(best ? accent.opacity(scheme == .dark ? 0.14 : 0.09) : (scheme == .dark ? Color.white.opacity(0.025) : Color.white.opacity(0.65)))
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(best ? accent.opacity(0.23) : Color.clear, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
