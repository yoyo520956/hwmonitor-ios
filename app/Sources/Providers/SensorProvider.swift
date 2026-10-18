import CoreMotion
import Foundation

/// 传感器采集器：CoreMotion（需 Motion & Fitness 权限）
/// 权限拒绝时优雅降级，不崩溃
public final class SensorProvider: @unchecked Sendable {
    public let category: MetricCategory = .sensors

    private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()

    public init() {}

    /// 权限状态（不触发系统弹窗的只读检查）
    public func authorizationStatus() -> CMAuthorizationStatus {
        CMMotionActivityManager.authorizationStatus()
    }

    public func statusText() -> (value: String, status: MetricStatus) {
        switch authorizationStatus() {
        case .notDetermined: return ("Not Requested", .degraded)
        case .denied: return ("Denied", .unauthorized)
        case .restricted: return ("Restricted", .unauthorized)
        case .authorized: return ("Authorized", .ok)
        @unknown default: return ("Unknown", .degraded)
        }
    }

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()
        let (permText, permStatus) = statusText()

        cards.append(MetricCard(
            id: "sensor.motionperm", name: "Motion Permission", value: permText,
            source: .appleAPI, method: "CMMotionActivityManager.authorizationStatus",
            limitation: permStatus == .unauthorized ? "Enable in Settings → Privacy & Security → Motion & Fitness to read live sensor data" : nil,
            status: permStatus, collectedAt: now, category: .sensors
        ))

        // 传感器可用性（设备硬件能力，不需要权限）
        cards.append(MetricCard(
            id: "sensor.accel", name: "Accelerometer", value: motionManager.isAccelerometerAvailable ? "Available" : "Unavailable",
            source: .appleAPI, method: "CMMotionManager.isAccelerometerAvailable",
            status: motionManager.isAccelerometerAvailable ? .ok : .unavailable,
            collectedAt: now, category: .sensors
        ))
        cards.append(MetricCard(
            id: "sensor.gyro", name: "Gyroscope", value: motionManager.isGyroAvailable ? "Available" : "Unavailable",
            source: .appleAPI, method: "CMMotionManager.isGyroAvailable",
            status: motionManager.isGyroAvailable ? .ok : .unavailable,
            collectedAt: now, category: .sensors
        ))
        cards.append(MetricCard(
            id: "sensor.magnet", name: "Magnetometer", value: motionManager.isMagnetometerAvailable ? "Available" : "Unavailable",
            source: .appleAPI, method: "CMMotionManager.isMagnetometerAvailable",
            status: motionManager.isMagnetometerAvailable ? .ok : .unavailable,
            collectedAt: now, category: .sensors
        ))
        cards.append(MetricCard(
            id: "sensor.devicemotion", name: "Device Motion (fused)", value: motionManager.isDeviceMotionAvailable ? "Available" : "Unavailable",
            source: .appleAPI, method: "CMMotionManager.isDeviceMotionAvailable",
            status: motionManager.isDeviceMotionAvailable ? .ok : .unavailable,
            collectedAt: now, category: .sensors
        ))

        // 采样率上限（设备能力标注）
        if motionManager.isAccelerometerAvailable {
            cards.append(MetricCard(
                id: "sensor.accelrate", name: "Accelerometer Max Rate",
                value: String(format: "%.0f Hz", motionManager.accelerometerUpdateInterval == 0 ? 0 : 1.0 / max(motionManager.accelerometerUpdateInterval, 0.001)),
                source: .derived, method: "1 / current update interval (configurable up to hardware max)",
                limitation: "iOS does not expose the hardware maximum rate constant",
                status: .degraded, collectedAt: now, category: .sensors
            ))
        }

        return cards
    }

    // MARK: - 实时采样（授权后由传感器页调用，页面退出必须 stop）

    /// 单次读取加速度/角速度/磁场
    public func readOnce() -> (accel: (x: Double, y: Double, z: Double)?, gyro: (x: Double, y: Double, z: Double)?, magnet: (x: Double, y: Double, z: Double)?) {
        guard motionManager.isDeviceMotionAvailable else { return (nil, nil, nil) }
        var result: (accel: (x: Double, y: Double, z: Double)?, gyro: (x: Double, y: Double, z: Double)?, magnet: (x: Double, y: Double, z: Double)?) = (nil, nil, nil)
        let semaphore = DispatchSemaphore(value: 0)
        motionManager.deviceMotionUpdateInterval = 0.1
        let handler: CMDeviceMotionHandler = { data, _ in
            if let d = data {
                result.accel = (d.userAcceleration.x, d.userAcceleration.y, d.userAcceleration.z)
                result.gyro = (d.rotationRate.x, d.rotationRate.y, d.rotationRate.z)
                let f = d.magneticField.field
                result.magnet = (f.x, f.y, f.z)
            }
            semaphore.signal()
        }
        motionManager.startDeviceMotionUpdates(to: .main, withHandler: handler)
        _ = semaphore.wait(timeout: .now() + 0.5)
        motionManager.stopDeviceMotionUpdates()
        return result
    }
}
