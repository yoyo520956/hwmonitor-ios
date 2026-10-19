import Foundation

// MARK: - 启动自检链
// 迁移自 LiveContainer LCTabView.task「进入 UI 前六连检」：
// 集中校验，问题即 UI 报错而非闪退；结果缓存供自检页展示。
// 用 async 统一异步模型（对应 LC 的 withUnsafeContinuation 桥思路）。

struct SelfCheckItem: Identifiable {
    let id: String
    let name: String
    let passed: Bool
    let detail: String
    let elapsedMS: Double
    /// 是否由降级路径兜底通过
    let degraded: Bool
}

final class LaunchSelfCheck: ObservableObject {
    static let shared = LaunchSelfCheck()

    @Published private(set) var items: [SelfCheckItem] = []
    @Published private(set) var finished = false
    @Published private(set) var lastRunAt: Date?

    private let lock = NSLock()

    private init() {}

    /// 全链自检（App 启动与手动触发共用）
    func runAll() async -> [SelfCheckItem] {
        var results: [SelfCheckItem] = []

        results.append(checkCore())
        results.append(checkDataSources())
        results.append(await checkLastRunHealth())
        results.append(checkStorageWritable())
        results.append(checkSamplingEngine())

        let snapshot = results
        await MainActor.run {
            self.items = snapshot
            self.finished = true
            self.lastRunAt = Date()
        }
        return snapshot
    }

    // MARK: 各检查项

    /// ① C 采集核心可用性
    private func checkCore() -> SelfCheckItem {
        let start = CFAbsoluteTimeGetCurrent()
        let before = MachCore.probeCallCount
        let sample = MachCore.cpuSample()
        let after = MachCore.probeCallCount
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let coreReached = after > before
        let passed = coreReached
        let detail: String
        if passed && sample != nil {
            detail = "C 核心可调用（host port 获取 \(after) 次），已产出首个差分样本"
        } else if passed {
            detail = "C 核心可调用；首拍差分基准已建立，下一个采样周期出值"
        } else {
            detail = "C 核心未响应，将回退纯 Swift 采集路径"
        }
        return SelfCheckItem(
            id: "core", name: "C 采集核心", passed: passed,
            detail: detail, elapsedMS: elapsed, degraded: !passed
        )
    }

    /// ② 数据源能力探测（关键结构的降级链预演）
    private func checkDataSources() -> SelfCheckItem {
        let start = CFAbsoluteTimeGetCurrent()
        let chain = FallbackChain<Double>("memory.total")
            .then("C 核心 host_info.max_mem") { MachCore.physicalMemory()?.value }
            .then("ProcessInfo.physicalMemory") { Double(ProcessInfo.processInfo.physicalMemory) }
        let probe = chain.probeAll()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let available = probe.filter { $0.available }.count
        let firstHit = probe.first { $0.available }?.name ?? "无"
        let passed = available > 0
        let detail = passed
            ? "内存总量 \(available)/\(probe.count) 级路径可用，首选命中：\(firstHit)"
            : "内存总量所有路径不可用"
        return SelfCheckItem(
            id: "datasource", name: "数据源降级链", passed: passed,
            detail: detail, elapsedMS: elapsed, degraded: available < probe.count
        )
    }

    /// ③ 上次运行健康检查（哨兵 + 异常遗言 + 心跳）
    private func checkLastRunHealth() async -> SelfCheckItem {
        let start = CFAbsoluteTimeGetCurrent()
        let leftovers = CrashSentinel.leftoverSentinels()
        let abnormal = CrashSentinel.lastRunWasAbnormal()
        let lastError = CrashSentinel.consumeLastError()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        var parts: [String] = []
        if let err = lastError {
            parts.append("上次异常：\(err.title)（\(err.reason.prefix(60))）")
        }
        if !leftovers.isEmpty {
            parts.append("残留哨兵：\(leftovers.joined(separator: "、"))")
        }
        let passed = lastError == nil && leftovers.isEmpty
        let detail = parts.isEmpty
            ? (abnormal ? "本次为首次启动" : "上次运行正常退出")
            : parts.joined(separator: "；")
        return SelfCheckItem(
            id: "health", name: "运行健康度", passed: passed,
            detail: detail, elapsedMS: elapsed, degraded: !passed
        )
    }

    /// ④ 存储可写（导出报告依赖）
    private func checkStorageWritable() -> SelfCheckItem {
        let start = CFAbsoluteTimeGetCurrent()
        let passed: Bool
        let detail: String
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let probeURL = docs.appendingPathComponent(".hwmon_selfcheck_probe")
            do {
                try "probe".write(to: probeURL, atomically: true, encoding: .utf8)
                try FileManager.default.removeItem(at: probeURL)
                passed = true
                detail = "Documents 目录可读写，导出功能就绪"
            } catch {
                passed = false
                detail = "Documents 不可写：\(error.localizedDescription)"
            }
        } else {
            passed = false
            detail = "无法定位 Documents 目录"
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        return SelfCheckItem(
            id: "storage", name: "存储可写性", passed: passed,
            detail: detail, elapsedMS: elapsed, degraded: false
        )
    }

    /// ⑤ 采样引擎状态
    private func checkSamplingEngine() -> SelfCheckItem {
        let start = CFAbsoluteTimeGetCurrent()
        let engine = MonitoringEngine.shared
        let hasSnapshot = !engine.snapshot.allCards.isEmpty
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let detail = hasSnapshot
            ? "引擎运行中（间隔 \(Int(engine.interval))s），快照含 \(engine.snapshot.allCards.count) 张指标卡"
            : "引擎已启动，等待首个全量快照"
        return SelfCheckItem(
            id: "engine", name: "采样引擎", passed: true,
            detail: detail, elapsedMS: elapsed, degraded: !hasSnapshot
        )
    }
}
