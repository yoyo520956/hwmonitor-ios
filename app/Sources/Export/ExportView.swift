import SwiftUI

// MARK: - 报告导出：预览 → JSON/CSV/文本 → ShareLink 原生分享

struct ExportView: View {
    @EnvironmentObject var engine: MonitoringEngine
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .json
    @State private var content: String = ""
    @State private var filename: String = "hwmonitor-report"

    enum ExportFormat: String, CaseIterable, Identifiable {
        case json = "JSON"
        case csv = "CSV"
        case text = "Text"
        var id: String { rawValue }
        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .csv: return "csv"
            case .text: return "txt"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(DSTokens.spaceL)

                ScrollView {
                    Text(content.isEmpty ? "Tap Refresh to generate the report from current live data." : content)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DSTokens.spaceL)
                        .textSelection(.enabled)
                }
                .background(Color(.secondarySystemGroupedBackground))
            }
            .navigationTitle("Device Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") { generate() }
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Clear History") {
                            engine.cpu.resetHistory()
                            engine.memory.resetHistory()
                            engine.network.resetHistory()
                            engine.storage.resetHistory()
                            content = ""
                        }
                        Spacer()
                        if !content.isEmpty {
                            ShareLink(item: exportItem, preview: SharePreview(filename + ".\(format.fileExtension)")) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .onAppear { generate() }
            .onChange(of: format) { _ in generate() }
        }
    }

    private var exportItem: String {
        // 写临时文件再分享（保留扩展名以便系统识别）
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename)-\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url.absoluteString
    }

    private func generate() {
        engine.rebuildSnapshot()
        let snap = engine.snapshot
        switch format {
        case .json:
            content = ReportBuilder.json(snap)
            filename = "hwmonitor-report"
        case .csv:
            content = ReportBuilder.csv(snap)
            filename = "hwmonitor-report"
        case .text:
            content = ReportBuilder.plainText(snap)
            filename = "hwmonitor-report"
        }
    }
}

// MARK: - 报告构建器

public enum ReportBuilder {
    public static func json(_ snap: Snapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .iso8601]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snap) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func csv(_ snap: Snapshot) -> String {
        var lines = ["id,name,value,unit,source,method,status,collected_at,limitation"]
        let df = ISO8601DateFormatter()
        for card in snap.allCards {
            lines.append([
                card.id, csvEscape(card.name), csvEscape(card.value),
                card.unit ?? "", card.source.rawValue, csvEscape(card.method),
                card.status.rawValue, df.string(from: card.collectedAt),
                csvEscape(card.limitation ?? ""),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    public static func plainText(_ snap: Snapshot) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var out = "HWMonitor Device Report\nGenerated: \(df.string(from: snap.createdAt))\n"
        out += "All values measured via public Apple APIs. N/A = system does not expose this data.\n"
        out += String(repeating: "=", count: 52) + "\n"
        let sections: [(String, [MetricCard])] = [
            ("DEVICE", snap.device), ("CPU", snap.cpu), ("MEMORY", snap.memory),
            ("STORAGE", snap.storage), ("BATTERY & THERMAL", snap.battery),
            ("GPU", snap.gpu), ("NETWORK", snap.network), ("SENSORS", snap.sensors),
            ("DISPLAY", snap.display), ("PRIVACY", snap.privacy),
        ]
        for (title, cards) in sections where !cards.isEmpty {
            out += "\n[\(title)]\n"
            for card in cards {
                out += "  \(card.name): \(card.value)"
                if card.status != .ok { out += "  (\(card.status.rawValue))" }
                out += "\n"
                out += "    ↳ \(card.method)\n"
                if let lim = card.limitation {
                    out += "    ⚠ \(lim)\n"
                }
            }
        }
        return out
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
