import Foundation

// MARK: - 降级链执行器
// 迁移自 LiveContainer「nil 检测推进降级链」：每级以 nil 判定推进，
// 命中即停并记录 provenance + 耗时，最终全部失败才报 unavailable。

struct TracedResult<T> {
    let value: T
    let level: ProvenanceLevel
    let path: String
    let elapsedMS: Double
}

struct FallbackChain<T> {
    private var stages: [(name: String, probe: () -> T?)] = []
    private let tag: String

    init(_ tag: String) {
        self.tag = tag
    }

    /// 追加一级降级路径（顺序即优先级）
    func then(_ name: String, _ probe: @escaping () -> T?) -> FallbackChain<T> {
        var copy = self
        copy.stages.append((name, probe))
        return copy
    }

    /// 依次尝试，返回首个命中结果（含 provenance 与耗时）
    func run() -> TracedResult<T>? {
        let start = CFAbsoluteTimeGetCurrent()
        for (index, stage) in stages.enumerated() {
            if let value = stage.probe() {
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                let level: ProvenanceLevel
                switch index {
                case 0: level = .primary
                case 1: level = .secondary
                default: level = .tertiary
                }
                return TracedResult(
                    value: value, level: level,
                    path: stage.name, elapsedMS: elapsed
                )
            }
        }
        return nil
    }

    /// 预演全部路径（自检用）：返回每级可用性与耗时，不提前退出
    func probeAll() -> [(name: String, available: Bool, elapsedMS: Double)] {
        stages.map { stage in
            let start = CFAbsoluteTimeGetCurrent()
            let ok = stage.probe() != nil
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            return (stage.name, ok, elapsed)
        }
    }
}
