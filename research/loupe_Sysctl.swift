//
//  SysctlHelper.swift
//  Loupe
//
//  Thin wrappers around sysctlbyname and uname to read kernel state that
//  isn't exposed through Foundation. Most iOS hardware identity ends up
//  here: hw.machine, hw.model, kern.osversion, kern.boottime, etc.
//

import Darwin
import Foundation

nonisolated enum SysctlHelper {
    /// Reads a null-terminated string from sysctl by name. Returns nil on failure.
    static func string(_ name: String) -> String? {
        var size: Int = 0
        if sysctlbyname(name, nil, &size, nil, 0) != 0 { return nil }
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        if sysctlbyname(name, &buffer, &size, nil, 0) != 0 { return nil }
        return String(cString: buffer)
    }

    /// Reads a scalar integer (Int32 or Int64) from sysctl by name.
    static func int64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        if sysctlbyname(name, &value, &size, nil, 0) == 0 {
            return value
        }
        var small: Int32 = 0
        var smallSize = MemoryLayout<Int32>.size
        if sysctlbyname(name, &small, &smallSize, nil, 0) == 0 {
            return Int64(small)
        }
        return nil
    }

    /// Reads a `timeval` from sysctl, such as `kern.boottime`.
    static func timeval(_ name: String) -> (seconds: Int, microseconds: Int)? {
        var tv = Darwin.timeval()
        var size = MemoryLayout<Darwin.timeval>.size
        if sysctlbyname(name, &tv, &size, nil, 0) == 0 {
            return (Int(tv.tv_sec), Int(tv.tv_usec))
        }
        return nil
    }

    /// Returns the hardware model identifier for the current device.
    /// On iOS this is `hw.machine` (e.g., "iPhone16,1"); on macOS
    /// `hw.machine` returns the CPU architecture ("arm64"), so we
    /// read `hw.model` instead (e.g., "MacBookPro18,2").
    static func modelIdentifier() -> String? {
        #if os(iOS)
        return string("hw.machine")
        #else
        return string("hw.model")
        #endif
    }

    /// Returns all fields of `utsname`, which iOS keeps surprisingly
    /// verbose: sysname, nodename, release, version, machine.
    static func uname() -> [String: String] {
        var info = utsname()
        guard Darwin.uname(&info) == 0 else { return [:] }

        func decode<T>(_ value: T) -> String {
            withUnsafePointer(to: value) { ptr in
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
}
