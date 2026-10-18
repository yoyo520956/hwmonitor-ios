import Foundation
import UIKit

/// 统一监控引擎：单例调度器，所有周期采样走同一条节拍
/// 三档间隔（1s / 5s / 30s）；进入后台暂停；前台恢复
public final class MonitoringEngine: @unchecked Sendable, ObservableObject {
    public static let shared = MonitoringEngine()

    // 采集器
    public let cpu = CPUProvider()
    public let memory = MemoryProvider()
    public let storage = StorageProvider()
    public let network = NetworkProvider()
    public let battery = BatteryProvider()
    public let device = DeviceProvider()
    public let gpu = GPUProvider()
    public let display = DisplayProvider()
    public let sensors = SensorProvider()
    public let privacy = PrivacyProvider()
    public let camera = CameraProvider()

    /// 各模块最新数据（UI 订阅）
    @Published public var snapshot: Snapshot = Snapshot()
    /// 采样间隔（秒）
    @Published public var interval: Double = 1.0 {
        didSet { if oldValue != interval { restartTimer() } }
    }
    @Published public var isRunning: Bool = true

    private var timer: Timer?
    private let lock = NSLock()
    /// tick 计数：5s 档每 5 tick 执行一次，30s 档每 30 tick
    private var tickCount: Int = 0

    private init() {
        // 电池监测常开（轻量）
        UIDevice.current.isBatteryMonitoringEnabled = true
        // 生命周期
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appDidEnterBackground() { pause() }
    @objc private func appWillEnterForeground() { resume() }

    public func pause() {
        lock.lock()
        timer?.invalidate()
        timer = nil
        lock.unlock()
    }

    public func resume() {
        guard isRunning else { return }
        restartTimer()
    }

    public func setRunning(_ running: Bool) {
        isRunning = running
        if running { resume() } else { pause() }
    }

    private func restartTimer() {
        lock.lock()
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.onTick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        lock.unlock()
    }

    /// 单次节拍：快速流（每 tick）+ 慢速快照（每 5 tick）
    private func onTick() {
        tickCount += 1

        // 流式采集：CPU / 内存 / 网络速率
        cpu.tick()
        memory.tick()
        network.tick()
        storage.tick()

        // 快照：低频全量刷新（每 5 tick，默认 5s）
        if tickCount % 5 == 0 {
            rebuildSnapshot()
        }
    }

    public func rebuildSnapshot() {
        let snap = Snapshot(
            createdAt: Date(),
            device: device.collect(),
            cpu: cpu.collect(),
            memory: memory.collect(),
            storage: storage.collect(),
            battery: battery.collect(),
            gpu: gpu.collect(),
            network: network.collect(),
            sensors: sensors.collect(),
            display: display.collect(),
            privacy: privacy.collect()
        )
        DispatchQueue.main.async { [weak self] in
            self?.snapshot = snap
        }
    }

    /// 诊断自检：执行全部模块采集，输出成败清单
    public func runDiagnostics() -> [(name: String, status: MetricStatus, note: String?)] {
        var results: [(String, MetricStatus, String?)] = []
        let modules: [(String, [MetricCard])] = [
            ("设备", device.collect()), ("CPU", cpu.collect()),
            ("内存", memory.collect()), ("存储", storage.collect()),
            ("电池与温度", battery.collect()), ("GPU", gpu.collect()),
            ("网络", network.collect()), ("传感器", sensors.collect()),
            ("显示", display.collect()), ("隐私", privacy.collect()),
            ("相机", camera.collect()),
        ]
        for (name, cards) in modules {
            // 模块内有 unavailable 的卡片不等于模块失败；取整体状态
            let worst: MetricStatus
            let criticalCount = cards.filter { $0.status == .unavailable }.count
            let unauthorizedCount = cards.filter { $0.status == .unauthorized }.count
            if cards.isEmpty {
                worst = .unavailable
            } else if criticalCount == cards.count {
                worst = .unavailable
            } else if unauthorizedCount > 0 {
                worst = .unauthorized
            } else if criticalCount > 0 {
                worst = .degraded
            } else {
                worst = .ok
            }
            let note: String? = {
                switch worst {
                case .ok: return nil
                case .degraded: return "\(criticalCount) item(s) limited by system"
                case .unauthorized: return "\(unauthorizedCount) item(s) need permission"
                case .unavailable: return "暂无数据"
                }
            }()
            results.append((name, worst, note))
        }
        return results
    }
}
