import SwiftUI

// MARK: - 自检页（能力矩阵）
// 迁移自 LiveContainer 启动自检链：进入 UI 前集中校验，此处可视化全链路状态。

struct SelfCheckView: View {
    @EnvironmentObject var engine: MonitoringEngine
    @StateObject private var checker = LaunchSelfCheck.shared

    var body: some View {
        ScrollView {
            VStack(spacing: DSTokens.spaceM) {
                summaryCard
                selfCheckSection
                moduleMatrixSection
                deepLinkSection
            }
            .padding(.horizontal, DSTokens.spaceL)
            .padding(.bottom, DSTokens.spaceXL)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("自检与能力矩阵")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { _ = await checker.runAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            if !checker.finished { _ = await checker.runAll() }
        }
    }

    // MARK: 总览卡

    private var summaryCard: some View {
        let items = checker.items
        let passed = items.filter(\.passed).count
        let degraded = items.filter { $0.degraded && $0.passed }.count
        let failed = items.filter { !$0.passed }.count
        let allGood = !items.isEmpty && failed == 0 && degraded == 0
        let icon: String = allGood ? "checkmark.seal.fill" : (failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle")
        let tint: Color = allGood ? DSColor.battery : (failed > 0 ? DSColor.thermal : .orange)
        let title: String = items.isEmpty
            ? "自检进行中…"
            : (allGood ? "全部检查通过" : "\(passed) 项通过 · \(degraded) 项降级 · \(failed) 项异常")
        return VStack(spacing: DSTokens.spaceS) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
            if let at = checker.lastRunAt {
                Text("上次自检：\(timeString(at))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSTokens.spaceL)
        .dsCard()
    }

    // MARK: 启动自检链结果

    private var selfCheckSection: some View {
        VStack(alignment: .leading, spacing: DSTokens.spaceS) {
            Text("启动自检链")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                if checker.items.isEmpty {
                    HStack {
                        ProgressView()
                        Text("正在执行 5 项检查…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, DSTokens.spaceL)
                } else {
                    ForEach(Array(checker.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 44) }
                        checkRow(item)
                    }
                }
            }
            .dsCard()
        }
    }

    private func checkRow(_ item: SelfCheckItem) -> some View {
        HStack(alignment: .top, spacing: DSTokens.spaceM) {
            Image(systemName: item.passed ? (item.degraded ? "arrow.down.circle.fill" : "checkmark.circle.fill") : "xmark.circle.fill")
                .font(.system(size: DSTokens.iconM))
                .foregroundStyle(item.passed ? (item.degraded ? .orange : DSColor.battery) : DSColor.thermal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(String(format: "%.1f ms", item.elapsedMS))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: 模块能力矩阵（降级链预演）

    private var moduleMatrixSection: some View {
        let entries = matrixEntries
        return VStack(alignment: .leading, spacing: DSTokens.spaceS) {
            Text("模块能力矩阵")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.leading, 38) }
                    HStack {
                        Image(systemName: entry.icon)
                            .font(.system(size: DSTokens.iconS))
                            .foregroundStyle(entry.color)
                            .frame(width: 22)
                        Text(entry.name)
                            .font(.caption)
                        Spacer()
                        Text(entry.statusText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(entry.statusColor)
                    }
                    .padding(.vertical, 7)
                }
            }
            .dsCard()
        }
    }

    private struct MatrixEntry: Identifiable {
        let id: String
        let name: String
        let icon: String
        let color: Color
        let statusText: String
        let statusColor: Color
    }

    private var matrixEntries: [MatrixEntry] {
        let cards = engine.snapshot.allCards
        func tally(_ prefixes: [String]) -> (ok: Int, degraded: Int, bad: Int) {
            let matched = cards.filter { c in prefixes.contains { c.id.hasPrefix($0) } }
            let ok = matched.filter { $0.status == .ok }.count
            let degraded = matched.filter { $0.status == .degraded }.count
            let bad = matched.filter { $0.status == .unavailable || $0.status == .unauthorized }.count
            return (ok, degraded, bad)
        }
        return FloatingModule.allCases.map { module in
            let (ok, degraded, bad) = tally(module.idPrefixes)
            var text = "无数据"
            var color = Color.secondary
            if ok + degraded + bad > 0 {
                if bad > 0 && ok == 0 && degraded == 0 {
                    text = "\(bad) 项受限"; color = DSColor.thermal
                } else if degraded > 0 || bad > 0 {
                    text = "\(ok) 正常 · \(degraded + bad) 受限"; color = .orange
                } else {
                    text = "\(ok) 项正常"; color = DSColor.battery
                }
            }
            return MatrixEntry(
                id: module.rawValue, name: module.title, icon: module.icon,
                color: module.color, statusText: text, statusColor: color
            )
        }
    }

    // MARK: 深链示例

    private var deepLinkSection: some View {
        let examples = DeepLinkRouter.examples
        return VStack(alignment: .leading, spacing: DSTokens.spaceS) {
            Text("深链与快捷指令")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(examples.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.0)
                                .font(.caption.weight(.medium))
                            Text(item.1)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = item.1
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(DSColor.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                }
            }
            .dsCard()
            Text("可在「快捷指令」中用「打开 URL」动作调用以上链接，直达对应功能页。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }
}
