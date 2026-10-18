import Charts
import SwiftUI

// MARK: - 监控页：实时曲线（Swift Charts）+ 采样控制

struct MonitorView: View {
    @EnvironmentObject var engine: MonitoringEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSTokens.spaceL) {
                    controlBar
                    cpuChart
                    memoryChart
                    networkChart
                    storageChart
                }
                .padding(.horizontal, DSTokens.spaceL)
                .padding(.bottom, DSTokens.spaceXL)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Monitor")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // 采样控制条
    private var controlBar: some View {
        HStack(spacing: DSTokens.spaceM) {
            Button {
                engine.setRunning(!engine.isRunning)
            } label: {
                Label(engine.isRunning ? "Pause" : "Resume", systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(DSPrimaryButtonStyle())

            Spacer()

            Picker("Interval", selection: $engine.interval) {
                Text("1s").tag(1.0)
                Text("5s").tag(5.0)
                Text("30s").tag(30.0)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 170)
        }
        .dsCard()
    }

    private var cpuChart: some View {
        chartCard(
            title: "CPU Usage", tint: DSColor.cpu, unit: "%",
            data: engine.cpu.history.map { SamplePoint(timestamp: $0.timestamp, value: $0.value * 100) },
            format: { String(format: "%.1f", $0) }
        )
    }

    private var memoryChart: some View {
        chartCard(
            title: "This App Memory (phys_footprint)", tint: DSColor.memory, unit: "MB",
            data: engine.memory.history.map { SamplePoint(timestamp: $0.timestamp, value: $0.value / 1_048_576) },
            format: { String(format: "%.1f", $0) }
        )
    }

    private var networkChart: some View {
        chartCard(
            title: "Network Throughput (all interfaces)", tint: DSColor.network, unit: "KB/s",
            data: engine.network.history.map { SamplePoint(timestamp: $0.timestamp, value: $0.value / 1024) },
            format: { String(format: "%.0f", $0) }
        )
    }

    private var storageChart: some View {
        chartCard(
            title: "Storage Usage Ratio", tint: DSColor.storage, unit: "%",
            data: engine.storage.history.map { SamplePoint(timestamp: $0.timestamp, value: $0.value * 100) },
            format: { String(format: "%.1f", $0) }
        )
    }

    private func chartCard(title: String, tint: Color, unit: String, data: [SamplePoint], format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: DSTokens.spaceS) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if data.count >= 2 {
                Chart(data) { point in
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.35), tint.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisValueLabel(format: .dateTime.minute().second())
                    }
                }
                .frame(height: 120)
                Text("Sampled every \(Int(engine.interval))s via unified engine tick — real measured values")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if engine.isRunning {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("Collecting samples…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 120)
            } else {
                Text("Sampling paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .dsCard(tint: tint)
    }
}

// MARK: - 诊断页：11 模块自检

struct DiagnosticsView: View {
    @EnvironmentObject var engine: MonitoringEngine
    @State private var results: [(name: String, status: MetricStatus, note: String?)] = []
    @State private var running = false
    @State private var lastRun: Date?

    var body: some View {
        List {
            Section {
                Button {
                    runDiagnostics()
                } label: {
                    HStack {
                        Image(systemName: "stethoscope")
                        Text(running ? "Running…" : "Run Full Diagnostics")
                    }
                }
                .disabled(running)
            } footer: {
                if let lastRun {
                    Text("Last run: \(lastRun.formatted(date: .omitted, time: .standard))")
                } else {
                    Text("Runs every collector once and reports each module's status. Restricted items are reported as N/A — never faked.")
                }
            }

            if !results.isEmpty {
                Section("Results") {
                    ForEach(results.indices, id: \.self) { index in
                        HStack {
                            Image(systemName: iconFor(results[index].status))
                                .foregroundStyle(DSColor.statusColor(results[index].status))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(results[index].name)
                                    .font(.subheadline)
                                if let note = results[index].note {
                                    Text(note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            StatusBadge(status: results[index].status)
                        }
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func iconFor(_ status: MetricStatus) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .unauthorized: return "lock.fill"
        case .unavailable: return "xmark.circle.fill"
        }
    }

    private func runDiagnostics() {
        running = true
        // 后台执行，避免主线程阻塞
        DispatchQueue.global(qos: .userInitiated).async {
            let result = engine.runDiagnostics()
            DispatchQueue.main.async {
                results = result
                lastRun = Date()
                running = false
            }
        }
    }
}
