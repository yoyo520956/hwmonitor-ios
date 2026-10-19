import Darwin
import Foundation

/// CPU 采集器（v3.0 混编版）
/// 首选路径：C 采集核心（hwmon_core.c）——tick 差分一次算完，缓存供 collect 使用
/// 降级路径：纯 Swift host_statistics64 / host_processor_info（保留自 v1.0，已验证）
/// CPU 频率：iOS 无公开 API → 系统限制标注
///
/// 统一节拍原则（迁移自 LiveContainer）：采样只在 tick() 发生一次，
/// collect() 只读缓存 —— 避免同一节拍内多次调用 mach 导致差分窗口漂移。
public final class CPUProvider: @unchecked Sendable, StreamableProvider {
    public let category: MetricCategory = .cpu

    private let lock = NSLock()
    // ── C 核心缓存 ──
    private var cachedSample: MachCore.CPUSample?
    private var cCoreHealthy = true
    private var lastUsagePath = "—"
    // ── Swift 降级路径状态 ──
    private var previousLoad: host_cpu_load_info = host_cpu_load_info()
    private var hasPrevLoad = false
    private var previousPerCore: [[UInt32]] = []
    private var _history: [SamplePoint] = []
    public var history: [SamplePoint] { get { lock.lock(); defer { lock.unlock() }; return _history } }

    public init() {}

    public func resetHistory() {
        lock.lock(); _history.removeAll(); lock.unlock()
    }

    /// 追加采样点（MonitoringEngine 统一节拍调用）——同时刷新缓存样本
    public func tick() {
        guard let sample = sampleOnce() else { return }
        lock.lock()
        cachedSample = sample
        _history.append(SamplePoint(value: sample.usage))
        if _history.count > 180 { _history.removeFirst(_history.count - 180) }
        lock.unlock()
    }

    /// 单次采样：C 核心优先，失败自动降级 Swift 路径（nil 检测推进降级链）
    private func sampleOnce() -> MachCore.CPUSample? {
        if cCoreHealthy, let s = MachCore.cpuSample() {
            lock.lock(); lastUsagePath = "C 核心 host_statistics(HOST_CPU_LOAD_INFO) 差分（混编）"; lock.unlock()
            return s
        }
        // 降级：Swift 路径（单次读取，避免连续调用吞噬差分基准）
        cCoreHealthy = false
        guard let sample = swiftSample() else { return nil }
        lock.lock(); lastUsagePath = "降级：纯 Swift host_statistics64 差分"; lock.unlock()
        return sample
    }

    /// 供 collect 使用的当前样本（不推进差分）
    public func currentSample() -> MachCore.CPUSample? {
        lock.lock(); defer { lock.unlock() }
        return cachedSample
    }

    /// 兼容接口（v1 测试与外部调用）：单次采样并返回总使用率
    /// 注意：会推进差分基准；同一节拍内请用 currentSample() 读缓存
    public func readTotalUsage() -> Double? {
        guard let sample = sampleOnce() else { return nil }
        lock.lock(); cachedSample = sample; lock.unlock()
        return sample.usage
    }

    public func usagePathDescription() -> String {
        lock.lock(); defer { lock.unlock() }
        return lastUsagePath
    }

    // MARK: - 降级路径：Swift tick 差分（v1.0 已验证实现）

    private func hostLoadInfo() -> host_cpu_load_info? {
        var size: mach_msg_type_number_t = UInt32(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics64(hostPort, HOST_CPU_LOAD_INFO, intPtr, &size)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    private func swiftSample() -> MachCore.CPUSample? {
        guard let load = hostLoadInfo() else { return nil }
        lock.lock()
        guard hasPrevLoad else {
            previousLoad = load
            hasPrevLoad = true
            lock.unlock()
            return nil   // 首拍只建立基准
        }
        let prev = previousLoad
        previousLoad = load
        lock.unlock()

        let user = Double(load.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return MachCore.CPUSample(
            usage: min((user + system + nice) / total, 1.0),
            user: user / total,
            system: system / total,
            idle: idle / total
        )
    }

    /// 每核使用率：C 核心优先 → Swift host_processor_info 降级
    public func readPerCoreUsage() -> [Double]? {
        if let cores = MachCore.perCoreUsage() { return cores }
        return swiftPerCoreUsage()
    }

    private func swiftPerCoreUsage() -> [Double]? {
        var cpuInfo: processor_info_array_t? = nil
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }

        let result = host_processor_info(
            hostPort, PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCPUInfo
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return nil }
        defer {
            let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            _ = vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var current: [[UInt32]] = []
        for core in 0..<Int(numCPUs) {
            let base = Int(CPU_STATE_MAX) * core
            current.append([
                UInt32(info[base + Int(CPU_STATE_USER)]),
                UInt32(info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(info[base + Int(CPU_STATE_IDLE)]),
                UInt32(info[base + Int(CPU_STATE_NICE)]),
            ])
        }

        lock.lock()
        let prev = previousPerCore
        previousPerCore = current
        lock.unlock()

        guard prev.count == current.count else { return nil }

        var usages: [Double] = []
        for i in 0..<current.count {
            let cur = current[i]
            let old = prev[i]
            let user = Double(cur[0] &- old[0])
            let system = Double(cur[1] &- old[1])
            let idle = Double(cur[2] &- old[2])
            let nice = Double(cur[3] &- old[3])
            let total = user + system + idle + nice
            let usage = total > 0 ? min((user + system + nice) / total, 1.0) : 0.0
            usages.append(usage)
        }
        return usages
    }

    // MARK: - MetricsProvider（拆分为小函数，防止 type-check 超时）

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()
        cards.append(contentsOf: staticCards(now: now))
        cards.append(contentsOf: usageCards(now: now))
        cards.append(contentsOf: perCoreCards(now: now))
        cards.append(Self.frequencyCard())
        return cards
    }

    /// 架构与核心数（静态项）
    private func staticCards(now: Date) -> [MetricCard] {
        let procInfo = ProcessInfo.processInfo
        var machine = SysctlReader.unameFields()["machine"] ?? "unknown"
        if machine.isEmpty { machine = "unknown" }

        let coreCount = procInfo.processorCount
        let activeCores = procInfo.activeProcessorCount
        let coreLimitation: String? = (activeCores != coreCount)
            ? "\(activeCores) active cores"
            : nil

        let archCard = MetricCard(
            id: "cpu.arch", name: "架构", value: machine,
            source: .appleAPI, method: "uname(3) machine 字段", status: .ok,
            collectedAt: now, category: .cpu
        )
        let coresCard = MetricCard(
            id: "cpu.cores", name: "核心数", value: "\(coreCount)",
            numeric: Double(coreCount), unit: "cores",
            source: .appleAPI, method: "ProcessInfo.processorCount",
            limitation: coreLimitation,
            status: .ok, collectedAt: now, category: .cpu
        )
        return [archCard, coresCard, Self.perfCoreCards(now: now)]
    }

    /// 性能核 / 能效核数量（A 系芯片大小核；C 核心 sysctl 优先）
    private static func perfCoreCards(now: Date) -> MetricCard {
        var pCores = MachCore.sysctlU64("hw.perflevel0.physicalcpu").map(Int64.init)
        var eCores = MachCore.sysctlU64("hw.perflevel1.physicalcpu").map(Int64.init)
        var path = "C 核心 sysctl hw.perflevel0/1.physicalcpu（A 系芯片大小核拓扑）"
        if pCores == nil || eCores == nil {
            pCores = SysctlReader.int64("hw.perflevel0.physicalcpu")
            eCores = SysctlReader.int64("hw.perflevel1.physicalcpu")
            path = "降级：Swift sysctl hw.perflevel0/1.physicalcpu"
        }
        let p = pCores ?? 0
        let e = eCores ?? 0
        if p + e > 0 {
            return MetricCard(
                id: "cpu.cluster", name: "性能核 / 能效核",
                value: "\(p) 性能核 + \(e) 能效核",
                source: .appleAPI, method: path,
                status: .ok, collectedAt: now, category: .cpu
            )
        }
        return MetricCard(
            id: "cpu.cluster", name: "性能核 / 能效核", value: "—",
            source: .appleAPI, method: "sysctl hw.perflevel0/1.physicalcpu",
            limitation: "此设备的系统接口未返回大小核拓扑",
            status: .unavailable, collectedAt: now, category: .cpu
        )
    }

    /// 总使用率与分量（读 tick 缓存，不推进差分）
    private func usageCards(now: Date) -> [MetricCard] {
        var cards: [MetricCard] = []
        let path = usagePathDescription()
        if let sample = currentSample() {
            cards.append(MetricCard(
                id: "cpu.usage", name: "CPU 使用率（总体）",
                value: PercentFormat.string(sample.usage),
                numeric: sample.usage, unit: "%",
                source: .computed, method: path,
                status: .ok, collectedAt: now, category: .cpu
            ))
            cards.append(MetricCard(
                id: "cpu.user", name: "用户态占比",
                value: PercentFormat.string(sample.user),
                numeric: sample.user, unit: "%",
                source: .computed, method: "tick 差分 ÷ 总 tick 数（与总量同拍）",
                status: .ok, collectedAt: now, category: .cpu
            ))
            cards.append(MetricCard(
                id: "cpu.system", name: "系统态占比",
                value: PercentFormat.string(sample.system),
                numeric: sample.system, unit: "%",
                source: .computed, method: "tick 差分 ÷ 总 tick 数（与总量同拍）",
                status: .ok, collectedAt: now, category: .cpu
            ))
        } else {
            cards.append(MetricCard(
                id: "cpu.usage", name: "CPU 使用率（总体）", value: "—",
                source: .appleAPI, method: path,
                limitation: "等待首次采样或系统接口不可用",
                status: .degraded, collectedAt: now, category: .cpu
            ))
        }
        return cards
    }

    /// 每核使用率
    private func perCoreCards(now: Date) -> [MetricCard] {
        guard let perCore = readPerCoreUsage(), !perCore.isEmpty else { return [] }
        let sum = perCore.reduce(0, +)
        let count = Double(perCore.count)
        let avg = sum / count

        var parts: [String] = []
        for (idx, u) in perCore.enumerated() {
            let pct = Int((u * 100).rounded())
            parts.append("C\(idx): \(pct)%")
        }
        let coreText = parts.joined(separator: "  ")
        let path = cCoreHealthy
            ? "C 核心 host_processor_info(PROCESSOR_CPU_LOAD_INFO) 每核差分（混编）"
            : "降级：Swift host_processor_info 每核差分"

        return [MetricCard(
            id: "cpu.percore", name: "每核使用率", value: coreText,
            numeric: avg, unit: "%",
            source: .computed, method: path,
            limitation: "执行中核数为 \(perCore.count)",
            status: .ok, collectedAt: now, category: .cpu
        )]
    }

    /// CPU 频率：iOS 无公开 API
    private static func frequencyCard() -> MetricCard {
        MetricCard.restricted(
            "cpu.freq", "CPU 频率",
            reason: "iOS 不开放 CPU 当前/最大频率的公开接口（hw.cpufrequency 无返回）；频率由系统按能效动态调度。",
            category: .cpu
        )
    }
}
