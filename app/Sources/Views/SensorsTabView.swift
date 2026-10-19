import CoreMotion
import SwiftUI

// MARK: - 传感器页：权限门 + 实时读数 + 相机规格（全部可点击进详情）

struct SensorsTabView: View {
    @EnvironmentObject var engine: MonitoringEngine

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MotionLiveRow()
                } header: {
                    Text("运动传感器")
                } footer: {
                    Text("运动读数仅在本页打开时采集，离开即停")
                }
                Section {
                    ForEach(engine.snapshot.sensors) { card in
                        NavigableCard(card: card) {
                            MetricCardListRow(card: card)
                        }
                    }
                    ForEach(engine.camera.collect()) { card in
                        NavigableCard(card: card) {
                            MetricCardListRow(card: card)
                        }
                    }
                } header: {
                    Text("相机硬件")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("传感器")
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
                Text("传感器实时读数")
                    .font(.subheadline.weight(.medium))
                Spacer()
                StatusBadge(status: motionManager.isDeviceMotionAvailable ? .ok : .unavailable)
            }

            Group {
                if authorized == .denied || authorized == .restricted {
                    Label(
                        "运动与健身权限被拒绝。可在 设置 → 隐私与安全性 → 运动与健身 中开启。",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(DSColor.statusColor(.unauthorized))
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("打开设置").font(.caption.weight(.semibold))
                    }
                } else if authorized == .notDetermined {
                    Text("需要「运动与健身」权限才能读取加速度计、陀螺仪与磁力计。所有数据仅在本机处理，不会上传。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        requestPermission()
                    } label: {
                        Text("允许运动与健身访问").font(.caption.weight(.semibold))
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
                format: "加速度 x %+.2f y %+.2f z %+.2f (g)\n旋转 x %+.2f y %+.2f z %+.2f (rad/s)\n重力 y %+.2f → 倾角 %.0f°",
                a.x, a.y, a.z, r.x, r.y, r.z, g.y,
                acos(min(max(abs(g.y), 0), 1)) * 180 / .pi
            )
        }
    }

    private func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}

// MARK: - 设置页：监控 / 悬浮窗 / 报告 / 关于

struct SettingsView: View {
    @EnvironmentObject var engine: MonitoringEngine
    @State private var showExport = false
    @AppStorage(FloatingConfig.enabledKey) private var floatingEnabled = true
    @State private var floatingModules: [FloatingModule] = FloatingConfig.loadModules()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("采样间隔", selection: $engine.interval) {
                        Text("1 秒").tag(1.0)
                        Text("5 秒").tag(5.0)
                        Text("30 秒").tag(30.0)
                    }
                    Toggle("自动刷新", isOn: Binding(
                        get: { engine.isRunning },
                        set: { engine.setRunning($0) }
                    ))
                } header: {
                    Text("监控")
                } footer: {
                    Text("进入后台自动暂停采样。采样频率越高耗电越多。")
                }

                // 悬浮窗自定义
                Section {
                    Toggle("启用悬浮窗", isOn: $floatingEnabled)
                    if floatingEnabled {
                        ForEach(FloatingModule.allCases) { module in
                            Toggle(isOn: moduleBinding(module)) {
                                HStack(spacing: 10) {
                                    Image(systemName: module.icon)
                                        .font(.system(size: DSTokens.iconM))
                                        .foregroundStyle(module.color)
                                        .frame(width: 24)
                                    Text(module.title)
                                }
                            }
                        }
                    }
                } header: {
                    Text("悬浮窗")
                } footer: {
                    Text("悬浮球可拖动到任意位置（自动吸附屏幕边缘），点按展开快捷监测面板。勾选的模块会出现在面板中，点击面板模块卡可直达对应功能页。")
                }

                Section {
                    NavigationLink {
                        SelfCheckView()
                    } label: {
                        Label("自检与能力矩阵", systemImage: "stethoscope")
                    }
                    Button {
                        showExport = true
                    } label: {
                        Label("导出设备报告", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("诊断与报告")
                } footer: {
                    Text("自检页展示启动自检链结果、各模块降级状态，以及可在「快捷指令」中使用的深链。")
                }

                Section {
                    LabeledContent("版本", value: "3.0.0")
                    LabeledContent("数据政策", value: "全部本地")
                    NavigationLink("开源致谢") {
                        NoticesView()
                    }
                } header: {
                    Text("关于")
                } footer: {
                    Text("所有数据均通过 Apple 公开 API 在本机采集，不上传任何内容。系统未开放的项目一律标注 N/A 并注明原因。")
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showExport) {
                ExportView()
            }
        }
    }

    private func moduleBinding(_ module: FloatingModule) -> Binding<Bool> {
        Binding<Bool>(
            get: { floatingModules.contains(module) },
            set: { on in
                if on {
                    if !floatingModules.contains(module) { floatingModules.append(module) }
                } else {
                    floatingModules.removeAll { $0 == module }
                }
                FloatingConfig.saveModules(floatingModules)
            }
        )
    }
}

// MARK: - 开源声明

struct NoticesView: View {
    var body: some View {
        List {
            Section {
                Text("本 App 的架构与部分实现思路参考了以下开源项目，许可证信息如下。未使用任何项目的品牌、图标与文案。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            notice("Loupe", "mysk-research/loupe", "MIT 许可证 © 2026 Mysk", "架构灵感：Provider/Signal 模型、权限门、sysctl 辅助模式。")
            notice("SystemInfoKit", "Kyome22/SystemInfoKit", "Apache 2.0 许可证 © 2020 Takuto Nakamura", "实现参考：host_statistics64 CPU tick 差分、vm_statistics64 内存分类、URL 卷资源值。")
            notice("iOS-System-Services", "Shmoopi/iOS-System-Services", "MIT 许可证 © 2012 Shmoopi LLC", "每核 CPU 使用率 host_processor_info(PROCESSOR_CPU_LOAD_INFO) 做法。")
            notice("DeviceKit", "devicekit/DeviceKit", "MIT 许可证", "型号标识映射表思路（表内容独立重建）")
            notice("Luminous", "andrealufino/Luminous", "MIT 许可证 © 2019 Andrea Lufino", "热状态/屏幕/进程信息细节参考")
        }
        .navigationTitle("开源致谢")
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
