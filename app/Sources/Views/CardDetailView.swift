import SwiftUI

// MARK: - 通用卡片详情页：每一条指标都可以点进来查看完整信息

struct CardDetailView: View {
    @EnvironmentObject var engine: MonitoringEngine
    let card: MetricCard

    var body: some View {
        ScrollView {
            VStack(spacing: DSTokens.spaceM) {
                heroValue
                infoList
                historySection
            }
            .padding(.horizontal, DSTokens.spaceL)
            .padding(.bottom, DSTokens.spaceXL)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 主值区

    private var heroValue: some View {
        VStack(spacing: DSTokens.spaceS) {
            StatusBadge(status: card.status)
            Text(card.value)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DSColor.statusColor(card.status))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
            if let unit = card.unit, !unit.isEmpty {
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(card.category.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(DSColor.categoryColor(card.category).opacity(0.15)))
                .foregroundStyle(DSColor.categoryColor(card.category))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSTokens.spaceXL)
        .dsCard()
    }

    // MARK: 信息明细

    private var infoList: some View {
        VStack(spacing: 0) {
            row(icon: "number.square", title: "当前数值", detail: card.value)
            Divider().padding(.leading, 44)
            row(icon: "arrow.triangle.branch", title: "数据来源", detail: sourceName(card.source))
            Divider().padding(.leading, 44)
            row(icon: "wrench.and.screwdriver", title: "采集方法", detail: card.method)
            if let limit = card.limitation, !limit.isEmpty {
                Divider().padding(.leading, 44)
                row(icon: "exclamationmark.triangle", title: "限制与说明", detail: limit)
            }
            Divider().padding(.leading, 44)
            row(icon: "clock", title: "采集时间", detail: timeString(card.collectedAt))
            Divider().padding(.leading, 44)
            row(icon: "link", title: "指标标识", detail: card.id)
        }
        .dsCard()
    }

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSTokens.spaceM) {
            Image(systemName: icon)
                .font(.system(size: DSTokens.iconM))
                .foregroundStyle(DSColor.categoryColor(card.category))
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private func sourceName(_ source: MetricSource) -> String {
        switch source {
        case .appleAPI: return "Apple 官方 API"
        case .computed: return "真实采样计算"
        case .derived: return "明确规则推导"
        case .systemRestricted: return "系统未开放"
        }
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt.string(from: date)
    }

    // MARK: 历史曲线（有流式数据的模块显示）

    @ViewBuilder
    private var historySection: some View {
        let points = historyFor(card)
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: DSTokens.spaceS) {
                HStack {
                    Text("近期趋势")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("最近 \(points.count) 个采样点")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                chart(points)
                    .frame(height: 120)
            }
            .padding(DSTokens.spaceM)
            .dsCard()
        }
    }

    private func chart(_ points: [SamplePoint]) -> some View {
        let values = points.map(\.value)
        let minV = (values.min() ?? 0)
        let maxV = (values.max() ?? 1)
        let range = max(maxV - minV, 0.0001)
        let width: CGFloat = 300
        let height: CGFloat = 110
        let step = points.count > 1 ? width / CGFloat(points.count - 1) : width
        let coords: [CGPoint] = points.enumerated().map { idx, pt in
            let y = height - CGFloat((pt.value - minV) / range) * height
            return CGPoint(x: CGFloat(idx) * step, y: y)
        }
        return ZStack {
            Path { path in
                path.move(to: coords.first ?? .zero)
                for c in coords.dropFirst() { path.addLine(to: c) }
            }
            .stroke(DSColor.categoryColor(card.category), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let last = coords.last {
                Circle().frame(width: 6, height: 6)
                    .foregroundStyle(DSColor.categoryColor(card.category))
                    .position(last)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DSTokens.radiusS)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    /// 从对应 Provider 拉取流式历史
    private func historyFor(_ card: MetricCard) -> [SamplePoint] {
        switch card.id {
        case "cpu.usage": return engine.cpu.history
        case "cpu.percore": return engine.cpu.history
        case "mem.used": return engine.memory.history
        case "net.rate": return engine.network.history
        default: return []
        }
    }
}

// MARK: - 可点击卡片包装（所有列表的卡片统一套这个）

struct NavigableCard<Content: View>: View {
    @EnvironmentObject var engine: MonitoringEngine
    let card: MetricCard
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationLink {
            CardDetailView(card: card)
        } label: {
            content()
        }
        .buttonStyle(.plain)
    }
}
