import SwiftUI

// MARK: - 总览页：关键指标 + 模块入口 + 诊断

struct OverviewView: View {
    @EnvironmentObject var engine: MonitoringEngine

    private var snap: Snapshot { engine.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSTokens.spaceM) {
                    heroCard
                    quickGrid
                    moduleEntries
                    diagnosticsPreview
                }
                .padding(.horizontal, DSTokens.spaceL)
                .padding(.bottom, DSTokens.spaceXL)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("总览")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // 顶部英雄卡：设备 + 系统 + 电量
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: DSTokens.spaceS) {
            HStack {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: DSTokens.iconXL, weight: .medium))
                    .foregroundStyle(DSColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(valueOf("dev.name", fallback: "—"))
                        .font(.title2.weight(.bold))
                    Text("\(valueOf("dev.systemname", fallback: "iOS")) · \(valueOf("dev.build", fallback: ""))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                batteryMini
            }
            Divider()
            HStack {
                miniStat(title: "CPU", value: valueOf("cpu.usage", fallback: "—"), color: DSColor.cpu)
                Divider().frame(height: 30)
                miniStat(title: "内存", value: valueOf("mem.used", fallback: "—"), color: DSColor.memory)
                Divider().frame(height: 30)
                miniStat(title: "存储", value: valueOf("sto.free", fallback: "—"), color: DSColor.storage)
            }
        }
        .dsCard(tint: DSColor.accent)
    }

    private var batteryMini: some View {
        HStack(spacing: DSTokens.spaceXS) {
            if let level = card("bat.level"), let pct = level.numeric {
                Image(systemName: batterySymbol(for: pct))
                    .foregroundStyle(DSColor.battery)
                Text(level.value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            } else {
                Image(systemName: "battery.0")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func batterySymbol(for fraction: Double) -> String {
        switch fraction {
        case ..<0.2: return "battery.0percent"
        case ..<0.5: return "battery.25percent"
        case ..<0.8: return "battery.50percent"
        default: return "battery.100percent"
        }
    }

    // 快速指标网格（全部可点击进详情）
    private var quickGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSTokens.spaceM) {
            ForEach(quickCards, id: \.id) { card in
                NavigationLink { CardDetailView(card: card) } label: {
                    MetricCardView(card: card, compact: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var quickCards: [MetricCard] {
        let ids = ["gpu.name", "net.status", "thermal.state", "disp.native"]
        return ids.compactMap { id in
            snap.allCards.first { $0.id == id }
        }
    }

    // 全部模块入口（点击直达硬件页对应分区）
    private var moduleEntries: some View {
        VStack(alignment: .leading, spacing: DSTokens.spaceS) {
            Text("功能模块")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: DSTokens.spaceS) {
                ForEach(FloatingModule.allCases) { module in
                    NavigationLink { HardwareView() } label: {
                        VStack(spacing: 6) {
                            Image(systemName: module.icon)
                                .font(.system(size: DSTokens.iconL))
                                .foregroundStyle(module.color)
                            Text(module.title)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DSTokens.spaceM)
                        .background(
                            RoundedRectangle(cornerRadius: DSTokens.radiusM, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // 诊断预览
    private var diagnosticsPreview: some View {
        NavigationLink {
            SelfCheckView()
        } label: {
            HStack {
                Image(systemName: "stethoscope")
                    .font(.system(size: DSTokens.iconL))
                    .foregroundStyle(DSColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("自检与能力矩阵")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("启动自检链 · 模块降级状态 · 深链快捷指令")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .dsCard()
        }
        .buttonStyle(.plain)
    }

    private func miniStat(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ id: String) -> MetricCard? {
        snap.allCards.first { $0.id == id }
    }

    private func valueOf(_ id: String, fallback: String) -> String {
        card(id)?.value ?? fallback
    }
}

// MARK: - 硬件页：设备 / CPU / GPU / 显示（全部行可点击进详情）

struct HardwareView: View {
    @EnvironmentObject var engine: MonitoringEngine

    private var snap: Snapshot { engine.snapshot }

    var body: some View {
        List {
            section("设备", cards: snap.device)
            section("CPU", cards: snap.cpu)
            section("GPU", cards: snap.gpu)
            section("显示", cards: snap.display)
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("硬件")
    }

    @ViewBuilder
    private func section(_ title: String, cards: [MetricCard]) -> some View {
        if !cards.isEmpty {
            Section {
                ForEach(cards) { card in
                    NavigableCard(card: card) {
                        MetricCardListRow(card: card)
                    }
                }
            } header: {
                Text(title)
            } footer: {
                Text("点击任意一栏可查看数据来源、采集方法与限制说明")
            }
        }
    }
}

// 列表行版指标卡（List 内用，节省空间）
struct MetricCardListRow: View {
    let card: MetricCard

    var body: some View {
        VStack(alignment: .leading, spacing: DSTokens.spaceXS) {
            HStack {
                Text(card.name)
                    .font(.subheadline)
                Spacer()
                StatusBadge(status: card.status)
            }
            Text(card.value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(card.status == .unavailable ? Color(.tertiaryLabel) : .primary)
                .lineLimit(3)
            Text(card.method)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let limitation = card.limitation {
                Text(limitation)
                    .font(.caption2)
                    .foregroundStyle(DSColor.statusColor(.degraded))
            }
        }
        .padding(.vertical, DSTokens.spaceXS)
    }
}

// MARK: - 系统页：网络 / 存储 / 电池 / 隐私（全部行可点击进详情）

struct SystemView: View {
    @EnvironmentObject var engine: MonitoringEngine

    private var snap: Snapshot { engine.snapshot }

    var body: some View {
        List {
            section("网络", cards: snap.network)
            section("存储", cards: snap.storage)
            section("电池与温度", cards: snap.battery)
            section("隐私与权限", cards: snap.privacy)
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("系统")
    }

    @ViewBuilder
    private func section(_ title: String, cards: [MetricCard]) -> some View {
        if !cards.isEmpty {
            Section {
                ForEach(cards) { card in
                    NavigableCard(card: card) {
                        MetricCardListRow(card: card)
                    }
                }
            } header: {
                Text(title)
            }
        }
    }
}
