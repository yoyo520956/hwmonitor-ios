import CoreMotion
import SwiftUI

// MARK: - 传感器页：权限门 + 实时读数 + 摄像头规格

struct SensorsTabView: View {
    @EnvironmentObject var engine: MonitoringEngine

    var body: some View {
        NavigationStack {
            List {
                Section("Motion Sensors") {
                    MotionLiveRow()
                }
                Section("Camera Hardware") {
                    ForEach(engine.snapshot.sensors.filter { $0.id.hasPrefix("sensor.") }) { card in
                        MetricCardListRow(card: card)
                    }
                    ForEach(engine.snapshot.sensors.filter { $0.id == "sensor.motionperm" }) { card in
                        MetricCardListRow(card: card)
                    }
                    ForEach(engine.camera.collect()) { card in
                        MetricCardListRow(card: card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sensors")
        }
    }
}

// 实时运动读数：进入页面启动、退出停止（防资源泄漏）
struct MotionLiveRow: View {
    @EnvironmentObject var engine: MonitoringEngine
    @State private var motionText = "—"
    @State private var authorized: CMAuthorizationStatus = .notDetermined
    private let motionManager = CMMotionManager()

    var body: some View {
        VStack(alignment: .leading, spacing: DSTokens.spaceS) {
            HStack {
                Text("Live Sensor Readings")
                    .font(.subheadline.weight(.medium))
                Spacer()
                StatusBadge(status: motionManager.isDeviceMotionAvailable ? .ok : .unavailable)
            }

            Group {
                if authorized == .denied || authorized == .restricted {
                    Label(
                        "Motion permission denied. Enable it in Settings → Privacy & Security → Motion & Fitness.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(DSColor.statusColor(.unauthorized))
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open Settings").font(.caption.weight(.semibold))
                    }
                } else if authorized == .notDetermined {
                    Text("Motion & Fitness permission is needed to read accelerometer, gyroscope and magnetometer. No data leaves this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        requestPermission()
                    } label: {
                        Text("Allow Motion Access").font(.caption.weight(.semibold))
                    }
                } else {
                    Text(motionText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                }
            }
        }
        .padding(.vertical, DSTokens.spaceXS)
        .onAppear {
            authorized = CMMotionActivityManager.authorizationStatus()
            if authorized == .authorized { startUpdates() }
        }
        .onDisappear {
            stopUpdates()
        }
    }

    private func requestPermission() {
        // CMMotionActivityManager 查询会触发系统授权弹窗
        let activityManager = CMMotionActivityManager()
        activityManager.queryActivityStarting(
            from: Date(), to: Date(), to: .main
        ) { _, _ in
            authorized = CMMotionActivityManager.authorizationStatus()
            if authorized == .authorized { startUpdates() }
        }
    }

    private func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.5
        motionManager.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let d = data else { return }
            let a = d.userAcceleration
            let r = d.rotationRate
            let g = d.gravity
            motionText = String(
                format: "accel  x %+.2f  y %+.2f  z %+.2f  (g)\nrot    x %+.2f  y %+.2f  z %+.2f  (rad/s)\ngravity y %+.2f  → tilt %.0f°",
                a.x, a.y, a.z, r.x, r.y, r.z, g.y,
                acos(min(max(abs(g.y), 0), 1)) * 180 / .pi
            )
        }
    }

    private func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: - 设置页：采样 / 导出 / 关于

struct SettingsView: View {
    @EnvironmentObject var engine: MonitoringEngine
    @State private var showExport = false

    var body: some View {
        NavigationStack {
            List {
                Section("Monitoring") {
                    Picker("Sampling Interval", selection: $engine.interval) {
                        Text("1 second").tag(1.0)
                        Text("5 seconds").tag(5.0)
                        Text("30 seconds").tag(30.0)
                    }
                    Toggle("Auto-refresh", isOn: Binding(
                        get: { engine.isRunning },
                        set: { engine.setRunning($0) }
                    ))
                } footer: {
                    Text("Sampling pauses automatically in background. Higher frequency costs more battery.")
                }

                Section("Report") {
                    Button {
                        showExport = true
                    } label: {
                        Label("Export Device Report", systemImage: "square.and.arrow.up")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Data Policy", value: "All local")
                    NavigationLink("Open-Source Notices") {
                        NoticesView()
                    }
                } footer: {
                    Text("All data is collected on-device via public Apple APIs. Nothing is uploaded. Items the system does not expose are marked N/A with reasons.")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showExport) {
                ExportView()
            }
        }
    }
}

// MARK: - 开源声明

struct NoticesView: View {
    var body: some View {
        List {
            Section("This app's architecture and selected implementations are informed by the following open-source projects. Their licenses are honored below.") {}
            notice("Loupe", "mysk-research/loupe", "MIT License © 2026 Mysk", "Architecture inspiration: Provider/Signal model, permission gates, sysctl helper pattern. Original branding, icons and copy are NOT used.")
            notice("SystemInfoKit", "Kyome22/SystemInfoKit", "Apache License 2.0 © 2020 Takuto Nakamura", "Implementation reference: host_statistics64 CPU tick delta, vm_statistics64 memory classification, URL volume resource values.")
            notice("iOS-System-Services", "Shmoopi/iOS-System-Services", "MIT License © 2012 Shmoopi LLC", "Per-core CPU usage via host_processor_info(PROCESSOR_CPU_LOAD_INFO).")
            notice("DeviceKit", "devicekit/DeviceKit", "MIT License", "Model-identifier mapping table concept (table rebuilt independently).")
            notice("Luminous", "andrealufino/Luminous", "MIT License © 2019 Andrea Lufino", "Reference for thermal state, display and process info details.")
        }
        .navigationTitle("Open-Source Notices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func notice(_ name: String, _ repo: String, _ license: String, _ usage: String) -> some View {
        VStack(alignment: .leading, spacing: DSTokens.spaceXS) {
            Text(name).font(.subheadline.weight(.semibold))
            Text(repo).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text(license).font(.caption).foregroundStyle(.secondary)
            Text(usage).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
