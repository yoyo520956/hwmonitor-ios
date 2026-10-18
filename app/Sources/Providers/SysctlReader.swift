import Darwin
import Foundation

/// sysctl 读取工具（自实现，键名为公开系统接口）
public enum SysctlReader {
    public static func string(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    public static func int64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        if sysctlbyname(name, &value, &size, nil, 0) == 0 { return value }
        var small: Int32 = 0
        var smallSize = MemoryLayout<Int32>.size
        if sysctlbyname(name, &small, &smallSize, nil, 0) == 0 { return Int64(small) }
        return nil
    }

    public static func uint64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname(name, &value, &size, nil, 0) == 0 { return value }
        var small: UInt32 = 0
        var smallSize = MemoryLayout<UInt32>.size
        if sysctlbyname(name, &small, &smallSize, nil, 0) == 0 { return UInt64(small) }
        return nil
    }

    /// utsname 全字段
    public static func unameFields() -> [String: String] {
        var info = utsname()
        guard uname(&info) == 0 else { return [:] }
        func decode<T>(_ v: T) -> String {
            withUnsafePointer(to: v) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                    String(cString: $0)
                }
            }
        }
        return [
            "sysname": decode(info.sysname),
            "nodename": decode(info.nodename),
            "release": decode(info.release),
            "version": decode(info.version),
            "machine": decode(info.machine),
        ]
    }

    /// 硬件型号标识符（iOS 上 hw.machine = "iPhone14,6"）
    public static func machineIdentifier() -> String? {
        #if os(iOS)
        return string("hw.machine")
        #else
        return string("hw.model")
        #endif
    }
}
