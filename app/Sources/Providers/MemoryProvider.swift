import Darwin
import Foundation

/// 内存采集器
/// 物理内存总量：host_basic_info.max_mem
/// 系统内存分类：vm_statistics64（64 位版，比 ISS 的 32 位 host_statistics 现代）
/// 当前 App 内存：task_vm_info.phys_footprint（iOS 15+ 前台 OOM 判据，等价 JetStream 协议）
public final class MemoryProvider: @unchecked Sendable, StreamableProvider {
    public let category: MetricCategory = .memory

    private let lock = NSLock()
    private var _history: [SamplePoint] = []
    public var history: [SamplePoint] {
        get { lock.lock(); defer { lock.unlock() }; return _history }
    }

    public init() {}

    public func resetHistory() {
        lock.lock(); _history.removeAll(); lock.unlock()
    }

    public func tick() {
        if let footprint = readProcessFootprintBytes() {
            lock.lock()
            _history.append(SamplePoint(value: footprint))
            if _history.count > 180 { _history.removeFirst(_history.count - 180) }
            lock.unlock()
        }
    }

    // MARK: - Mach 层读取

    private var pageSize: Double {
        // C 核心优先（hwmon_page_size → sysctl hw.pagesize）
        let cPage = Double(hwmon_page_size())
        if cPage > 0 { return cPage }
        var size: vm_size_t = 0
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }
        _ = host_page_size(hostPort, &size)
        return Double(size)
    }

    /// 物理内存总量（三级降级链：C 核心 host_info → Swift host_info → ProcessInfo）
    public func readPhysicalMemoryBytes() -> Double {
        let chain = FallbackChain<Double>("mem.total")
            .then("C 核心 host_info(HOST_BASIC_INFO).max_mem（混编）") {
                MachCore.physicalMemory()?.value
            }
            .then("Swift host_info(HOST_BASIC_INFO).max_mem") {
                let v = MemoryProvider.swiftPhysicalMemory()
                return v > 0 ? v : nil
            }
            .then("ProcessInfo.physicalMemory") {
                let v = Double(ProcessInfo.processInfo.physicalMemory)
                return v > 0 ? v : nil
            }
        guard let result = chain.run() else { return 0 }
        lastTotalPath = result.path
        return result.value
    }

    /// 物理内存总量采集路径（供卡片展示 provenance）
    private var lastTotalPath: String = "host_info(HOST_BASIC_INFO).max_mem"

    private static func swiftPhysicalMemory() -> Double {
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }
        var info = host_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_info(hostPort, HOST_BASIC_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.max_mem)
    }

    /// VM 分类快照（统一中间结构：页数 + 命中路径）
    private struct VMSnapshot {
        let active: Double
        let inactive: Double
        let speculative: Double
        let wired: Double
        let compressed: Double
        let purgeable: Double
        let external: Double
        let free: Double
        let path: String
    }

    /// VM 统计（双路径：C 核心 vm_statistics64 → Swift vm_statistics64）
    private func readVMSnapshot() -> VMSnapshot? {
        if let c = MachCore.vmStats() {
            let path = c.degraded
                ? "降级：C 核心 32 位 host_statistics(HOST_VM_INFO)"
                : "C 核心 vm_statistics64（混编）"
            return VMSnapshot(
                active: c.stats.active, inactive: c.stats.inactive,
                speculative: c.stats.speculative, wired: c.stats.wired,
                compressed: c.stats.compressed, purgeable: c.stats.purgeable,
                external: c.stats.external, free: c.stats.free, path: path
            )
        }
        guard let stats = readVMStatistics64() else { return nil }
        return VMSnapshot(
            active: Double(stats.active_count), inactive: Double(stats.inactive_count),
            speculative: Double(stats.speculative_count), wired: Double(stats.wire_count),
            compressed: Double(stats.compressor_page_count), purgeable: Double(stats.purgeable_count),
            external: Double(stats.external_page_count), free: Double(stats.free_count),
            path: "降级：Swift vm_statistics64"
        )
    }

    private func readVMStatistics64() -> vm_statistics64? {
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }
        return result == KERN_SUCCESS ? stats : nil
    }

    /// 当前 App 物理内存占用（phys_footprint，字节）
    public func readProcessFootprintBytes() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint)
    }

    // MARK: - MetricsProvider

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()
        let page = pageSize

        // 物理内存总量
        let total = readPhysicalMemoryBytes()
        if total > 0 {
            cards.append(MetricCard(
                id: "mem.total", name: "物理内存", value: ByteFormat.gibibytes(total),
                numeric: total, unit: "bytes",
                source: .appleAPI, method: lastTotalPath,
                status: .ok, collectedAt: now, category: .memory
            ))
        }

        // 系统内存分类统计
        if let snap = readVMSnapshot() {
            let active = snap.active * page
            let inactive = snap.inactive * page
            let speculative = snap.speculative * page
            let wired = snap.wired * page
            let compressed = snap.compressed * page
            let purgeable = snap.purgeable * page
            let external = snap.external * page
            let free = snap.free * page
            let vmPath = snap.path

            let cached = purgeable + external
            let app = active + inactive + speculative - cached
            let pressure = wired + compressed
            let using = app + pressure

            if total > 0 {
                cards.append(MetricCard(
                    id: "mem.used", name: "已用内存", value: ByteFormat.gibibytes(using),
                    numeric: using, unit: "bytes",
                    source: .computed, method: "\(vmPath) 分类求和 × 页大小（app 段 + 压力段）",
                    status: .ok, collectedAt: now, category: .memory
                ))
                cards.append(MetricCard(
                    id: "mem.pressure", name: "内存压力", value: PercentFormat.string(pressure / total),
                    numeric: pressure / total, unit: "%",
                    source: .computed, method: "公式：(wired + compressed) / max_mem",
                    status: .ok, collectedAt: now, category: .memory
                ))
            }
            cards.append(MetricCard(
                id: "mem.app", name: "应用内存", value: ByteFormat.gibibytes(app),
                numeric: app, unit: "bytes",
                source: .computed, method: "公式：active + inactive + speculative - purgeable - external（页数 × 页大小）",
                status: .ok, collectedAt: now, category: .memory
            ))
            cards.append(MetricCard(
                id: "mem.wired", name: "固定内存 (wired)", value: ByteFormat.gibibytes(wired),
                numeric: wired, unit: "bytes",
                source: .computed, method: "\(vmPath) wired 页数（内核锁定不可换出）", status: .ok,
                collectedAt: now, category: .memory
            ))
            cards.append(MetricCard(
                id: "mem.active", name: "活跃内存 (active)", value: ByteFormat.gibibytes(active),
                numeric: active, unit: "bytes",
                source: .computed, method: "\(vmPath) active 页数（最近使用）", status: .ok,
                collectedAt: now, category: .memory
            ))
            cards.append(MetricCard(
                id: "mem.inactive", name: "非活跃内存 (inactive)", value: ByteFormat.gibibytes(inactive),
                numeric: inactive, unit: "bytes",
                source: .computed, method: "\(vmPath) inactive 页数（可回收缓存）", status: .ok,
                collectedAt: now, category: .memory
            ))
            cards.append(MetricCard(
                id: "mem.compressed", name: "已压缩", value: ByteFormat.gibibytes(compressed),
                numeric: compressed, unit: "bytes",
                source: .computed, method: "vm_statistics64 压缩器页数", status: .ok,
                collectedAt: now, category: .memory
            ))
            cards.append(MetricCard(
                id: "mem.free", name: "可用", value: ByteFormat.gibibytes(free),
                numeric: free, unit: "bytes",
                source: .computed, method: "vm_statistics64 空闲页数", status: .ok,
                collectedAt: now, category: .memory
            ))
        }

        // 当前 App 内存（与"系统内存统计"明确区分）
        if let footprint = readProcessFootprintBytes() {
            cards.append(MetricCard(
                id: "mem.footprint", name: "本 App 占用 (phys_footprint)", value: ByteFormat.gibibytes(footprint),
                numeric: footprint, unit: "bytes",
                source: .appleAPI, method: "task_info(TASK_VM_INFO).phys_footprint",
                limitation: "仅统计本 App；iOS 不开放其他 App 的内存占用",
                status: .ok, collectedAt: now, category: .memory
            ))
        }

        return cards
    }
}
