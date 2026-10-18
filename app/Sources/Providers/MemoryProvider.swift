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
        var size: vm_size_t = 0
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }
        _ = host_page_size(hostPort, &size)
        return Double(size)
    }

    public func readPhysicalMemoryBytes() -> Double {
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
                id: "mem.total", name: "Physical Memory", value: ByteFormat.gibibytes(total),
                numeric: total, unit: "bytes",
                source: .appleAPI, method: "host_info(HOST_BASIC_INFO).max_mem",
                status: .ok, collectedAt: now, category: .memory
            ))
        }

        // 系统内存分类统计
        if let stats = readVMStatistics64() {
            let active = Double(stats.active_count) * page
            let inactive = Double(stats.inactive_count) * page
            let speculative = Double(stats.speculative_count) * page
            let wired = Double(stats.wire_count) * page
            let compressed = Double(stats.compressor_page_count) * page
            let purgeable = Double(stats.purgeable_count) * page
            let external = Double(stats.external_page_count) * page
            let free = Double(stats.free_count) * page

            let cached = purgeable + external
            let app = active + inactive + speculative - cached
            let pressure = wired + compressed
            let using = app + pressure

            if total > 0 {
                cards.append(MetricCard(
                    id: "mem.used", name: "Memory In Use", value: ByteFormat.gibibytes(using),
                    numeric: using, unit: "bytes",
                    source: .computed, method: "vm_statistics64: app(active+inactive+speculative-cached) + pressure(wired+compressed), × page size",
                    status: .ok, collectedAt: now, category: .memory
                ))
                cards.append(MetricCard(
                    id: "mem.pressure", name: "Memory Pressure", value: PercentFormat.string(pressure / total),
                    numeric: pressure / total, unit: "%",
                    source: .computed, method: "(wired + compressed) / max_mem",
                    status: .ok, collectedAt: now, category: .memory
                ))
            }
            cards.append(MetricCard(
                id: "mem.app", name: "App Memory", value: ByteFormat.gibibytes(app),
                numeric: app, unit: "bytes",
                source: .computed, method: "active + inactive + speculative - purgeable - external (pages × page size)",
                status: .ok, collectedAt: now, category: .memory
            ))
            cards.append(MetricCard(
                id: "mem.wired", name: "Wired", value: ByteFormat.gibibytes(wired),
                numeric: wired, unit: "bytes",
                source: .computed, method: "vm_statistics64.wire_count", status: .ok,
                collectedAt: now, category: .memory
            ))
            cards.append(MetricCard(
                id: "mem.compressed", name: "Compressed", value: ByteFormat.gibibytes(compressed),
                numeric: compressed, unit: "bytes",
                source: .computed, method: "vm_statistics64.compressor_page_count", status: .ok,
                collectedAt: now, category: .memory
            ))
            cards.append(MetricCard(
                id: "mem.free", name: "Free", value: ByteFormat.gibibytes(free),
                numeric: free, unit: "bytes",
                source: .computed, method: "vm_statistics64.free_count", status: .ok,
                collectedAt: now, category: .memory
            ))
        }

        // 当前 App 内存（与"系统内存统计"明确区分）
        if let footprint = readProcessFootprintBytes() {
            cards.append(MetricCard(
                id: "mem.footprint", name: "This App (Phys Footprint)", value: ByteFormat.gibibytes(footprint),
                numeric: footprint, unit: "bytes",
                source: .appleAPI, method: "task_info(TASK_VM_INFO).phys_footprint",
                limitation: "Measures this app only; iOS does not expose other apps' memory",
                status: .ok, collectedAt: now, category: .memory
            ))
        }

        return cards
    }
}
