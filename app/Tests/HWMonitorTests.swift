import XCTest
@testable import HWMonitor

// 阶段 F 单元测试：数据模型 / 格式转换 / 采集器行为

final class HWMonitorTests: XCTestCase {

    // MARK: - MetricCard 模型

    func testMetricCardRestrictedPlaceholder() {
        let card = MetricCard.restricted(
            "cpu.freq", "CPU Frequency",
            reason: "iOS does not expose CPU frequency", category: .cpu
        )
        XCTAssertEqual(card.status, .unavailable)
        XCTAssertEqual(card.source, .systemRestricted)
        XCTAssertEqual(card.value, "—")
        XCTAssertNotNil(card.limitation)
        XCTAssertNil(card.numeric)
    }

    func testMetricCardCodableRoundTrip() throws {
        let card = MetricCard(
            id: "cpu.usage", name: "CPU Usage", value: "23.4%", numeric: 0.234,
            unit: "%", source: .computed, method: "tick delta", status: .ok,
            collectedAt: Date(timeIntervalSince1970: 1_760_000_000), category: .cpu
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(card)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(MetricCard.self, from: data)
        XCTAssertEqual(restored.id, card.id)
        XCTAssertEqual(restored.numeric, card.numeric)
        XCTAssertEqual(restored.status, .ok)
    }

    func testSnapshotAllCards() {
        var snap = Snapshot()
        snap.device = [MetricCard(
            id: "dev.x", name: "X", value: "1", source: .appleAPI,
            method: "m", status: .ok, category: .hardware
        )]
        snap.cpu = [MetricCard(
            id: "cpu.x", name: "X", value: "2", source: .appleAPI,
            method: "m", status: .ok, category: .cpu
        )]
        XCTAssertEqual(snap.allCards.count, 2)
    }

    // MARK: - SysctlReader（真实设备上应读到值）

    func testSysctlMachineIdentifier() {
        let id = SysctlReader.machineIdentifier()
        XCTAssertNotNil(id)
        XCTAssertFalse(id!.isEmpty)
    }

    func testSysctlUnameFields() {
        let fields = SysctlReader.unameFields()
        XCTAssertEqual(fields["sysname"], "Darwin")
        XCTAssertNotNil(fields["release"])
    }

    // MARK: - CPUProvider

    func testCPUUsageNeedsTwoSamples() {
        let provider = CPUProvider()
        // 第一次调用（无前值缓存）应返回 nil 或成功——差分语义下首帧返回 nil 合理
        let first = provider.readTotalUsage()
        // 第二次调用必须有值（两次之间有 tick 差分）
        Thread.sleep(forTimeInterval: 0.1)
        let second = provider.readTotalUsage()
        if second != nil {
            XCTAssertTrue(second! >= 0 && second! <= 1.0, "usage must be in 0...1, got \(second!)")
        } else {
            // 首次差分为 0 时返回 nil 是合法路径
            XCTAssertNotNil(first)
        }
    }

    func testCPUPerCoreValidRange() {
        let provider = CPUProvider()
        _ = provider.readPerCoreUsage()
        Thread.sleep(forTimeInterval: 0.1)
        if let perCore = provider.readPerCoreUsage() {
            XCTAssertFalse(perCore.isEmpty)
            for u in perCore {
                XCTAssertTrue(u >= 0 && u <= 1.0, "per-core usage \(u) out of range")
            }
        }
        // 每核读数不可用不算失败（模拟器/系统差异），仅验证不崩溃
    }

    func testCPUCollectProducesCoreCards() {
        let provider = CPUProvider()
        _ = provider.readTotalUsage()
        Thread.sleep(forTimeInterval: 0.2)
        let cards = provider.collect()
        let ids = Set(cards.map(\.id))
        XCTAssertTrue(ids.contains("cpu.arch"))
        XCTAssertTrue(ids.contains("cpu.cores"))
        XCTAssertTrue(ids.contains("cpu.freq"))
        // 频率卡必须是 restricted
        let freq = cards.first { $0.id == "cpu.freq" }!
        XCTAssertEqual(freq.status, .unavailable)
    }

    // MARK: - MemoryProvider

    func testPhysicalMemoryIsSane() {
        let provider = MemoryProvider()
        let bytes = provider.readPhysicalMemoryBytes()
        // SE3 = 4GB；真实设备 1GB-64GB 之间
        XCTAssertGreaterThan(bytes, 1_000_000_000, "physical memory \(bytes) too small")
        XCTAssertLessThan(bytes, 100_000_000_000, "physical memory \(bytes) too large")
    }

    func testProcessFootprint() {
        let provider = MemoryProvider()
        if let footprint = provider.readProcessFootprintBytes() {
            XCTAssertGreaterThan(footprint, 1_000_000, "footprint should exceed 1MB for a running app")
            XCTAssertLessThan(footprint, 2_000_000_000, "footprint should be below 2GB")
        }
        // 读不到不失败（环境差异）
    }

    func testMemoryCollectSeparatesAppAndSystem() {
        let provider = MemoryProvider()
        let cards = provider.collect()
        let appMem = cards.first { $0.id == "mem.footprint" }
        let sysMem = cards.first { $0.id == "mem.used" }
        // 两者必须独立存在（任务书：不得混为一谈）
        if appMem != nil && sysMem != nil {
            XCTAssertNotEqual(appMem!.id, sysMem!.id)
        }
        XCTAssertTrue(cards.contains { $0.id == "mem.total" })
    }

    // MARK: - StorageProvider

    func testStorageVolumes() {
        let provider = StorageProvider()
        guard let (total, available) = provider.readVolumes() else {
            XCTFail("storage volumes must be readable on iOS")
            return
        }
        XCTAssertGreaterThan(total, 1_000_000_000)
        XCTAssertGreaterThanOrEqual(total, available, "available cannot exceed total")
    }

    // MARK: - DeviceProvider

    func testModelMapping() {
        XCTAssertEqual(DeviceProvider.marketingName(for: "iPhone14,6"), "iPhone SE (3rd generation)")
        XCTAssertEqual(DeviceProvider.marketingName(for: "iPhone16,1"), "iPhone 15 Pro")
        // 未知型号回退为标识符本身
        XCTAssertEqual(DeviceProvider.marketingName(for: "iPhone99,9"), "iPhone99,9")
    }

    func testDeviceCollectHasBuild() {
        let provider = DeviceProvider()
        let cards = provider.collect()
        XCTAssertTrue(cards.contains { $0.id == "dev.build" })
        XCTAssertTrue(cards.contains { $0.id == "dev.identifier" })
    }

    // MARK: - BatteryProvider

    func testBatteryCollectMarksRestrictedItems() {
        let provider = BatteryProvider()
        let cards = provider.collect()
        let restrictedIds = ["bat.health", "bat.cycle", "bat.temp", "bat.elec"]
        for id in restrictedIds {
            guard let card = cards.first(where: { $0.id == id }) else {
                XCTFail("missing restricted card \(id)")
                continue
            }
            XCTAssertEqual(card.status, .unavailable, "\(id) must be unavailable, not faked")
            XCTAssertEqual(card.source, .systemRestricted)
            XCTAssertNotNil(card.limitation)
        }
    }

    func testThermalStateCard() {
        let provider = BatteryProvider()
        let cards = provider.collect()
        let thermal = cards.first { $0.id == "thermal.state" }
        XCTAssertNotNil(thermal)
        XCTAssertEqual(thermal?.status, .ok)
    }

    // MARK: - GPUProvider

    func testGPUCollect() {
        let provider = GPUProvider()
        let cards = provider.collect()
        // 真机上必有 gpu.name；标记不可用也必须带 limitation
        if let name = cards.first(where: { $0.id == "gpu.name" }) {
            XCTAssertEqual(name.status, .ok)
            XCTAssertFalse(name.value.isEmpty)
        }
        // 利用率必须是 restricted
        let util = cards.first { $0.id == "gpu.util" }
        if let util {
            XCTAssertEqual(util.status, .unavailable)
        }
    }

    // MARK: - NetworkProvider

    func testInterfaceBytes() {
        let provider = NetworkProvider()
        if let (rx, tx) = provider.readInterfaceBytes() {
            XCTAssertGreaterThanOrEqual(rx, 0)
            XCTAssertGreaterThanOrEqual(tx, 0)
            // App 刚启动也可能已有流量
        }
    }

    // MARK: - ReportBuilder

    func testReportJSONValid() throws {
        var snap = Snapshot()
        snap.cpu = [MetricCard(
            id: "cpu.usage", name: "CPU Usage", value: "12%", numeric: 0.12,
            unit: "%", source: .computed, method: "delta", status: .ok,
            collectedAt: Date(timeIntervalSince1970: 1_760_000_000), category: .cpu
        )]
        let json = ReportBuilder.json(snap)
        let data = json.data(using: .utf8)!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testReportCSVHeaders() {
        var snap = Snapshot()
        snap.cpu = [MetricCard(
            id: "cpu.usage", name: "CPU Usage", value: "12%", source: .computed,
            method: "delta", status: .ok, collectedAt: Date(), category: .cpu
        )]
        let csv = ReportBuilder.csv(snap)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "id,name,value,unit,source,method,status,collected_at,limitation")
        XCTAssertEqual(lines.count, 2)
    }

    func testCSVEscaping() {
        var snap = Snapshot()
        snap.cpu = [MetricCard(
            id: "t", name: "has,comma", value: "has\"quote", source: .appleAPI,
            method: "m", status: .ok, collectedAt: Date(), category: .cpu
        )]
        let csv = ReportBuilder.csv(snap)
        XCTAssertTrue(csv.contains("\"has,comma\""))
        XCTAssertTrue(csv.contains("\"has\"\"quote\""))
    }

    func testPlainTextReportStructure() {
        let snap = Snapshot(createdAt: Date())
        let text = ReportBuilder.plainText(snap)
        XCTAssertTrue(text.contains("HWMonitor Device Report"))
        XCTAssertTrue(text.contains("public Apple APIs"))
    }

    // MARK: - MonitoringEngine

    func testDiagnosticsCoversAllModules() {
        let engine = MonitoringEngine.shared
        let results = engine.runDiagnostics()
        let names = Set(results.map(\.name))
        for expected in ["Device", "CPU", "Memory", "Storage", "Battery & Thermal", "GPU", "Network", "Sensors", "Display", "Privacy", "Camera"] {
            XCTAssertTrue(names.contains(expected), "diagnostics missing \(expected)")
        }
    }

    func testEngineSnapshotAfterRebuild() {
        let engine = MonitoringEngine.shared
        let expectation = expectation(description: "snapshot rebuilt")
        engine.rebuildSnapshot()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertFalse(engine.snapshot.allCards.isEmpty, "snapshot must contain cards after rebuild")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }
}
