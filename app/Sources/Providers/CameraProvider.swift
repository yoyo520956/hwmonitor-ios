import AVFoundation
import Foundation

/// 摄像头规格采集器：AVCaptureDevice.DiscoverySession 枚举（读格式不需要相机授权）
public final class CameraProvider: @unchecked Sendable {
    public let category: MetricCategory = .camera

    public init() {}

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()

        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInTrueDepthCamera,
        ]
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes, mediaType: .video, position: .unspecified
        )
        let devices = session.devices

        if devices.isEmpty {
            cards.append(MetricCard(
                id: "cam.count", name: "摄像头", value: "0",
                source: .appleAPI, method: "AVCaptureDevice.DiscoverySession(.video)",
                limitation: "未发现摄像头（模拟器或受限设备）",
                status: .unavailable, collectedAt: now, category: .camera
            ))
            return cards
        }

        cards.append(MetricCard(
            id: "cam.count", name: "发现的摄像头", value: "\(devices.count)",
            numeric: Double(devices.count), unit: "lenses",
            source: .appleAPI, method: "AVCaptureDevice.DiscoverySession(.video, position: .unspecified)",
            status: .ok, collectedAt: now, category: .camera
        ))

        for (index, device) in devices.prefix(6).enumerated() {
            let position: String
            switch device.position {
            case .back: position = "后置"
            case .front: position = "前置"
            default: position = "未知"
            }
            let lensLabel = device.deviceType == .builtInTrueDepthCamera
                ? "深感 (TrueDepth)" : "镜头 \(index + 1)"

            // 最大分辨率与最高帧率
            var maxDim: (w: Int32, h: Int32) = (0, 0)
            var maxFPS: Double = 0
            for format in device.formats {
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                if dims.width * dims.height > maxDim.w * maxDim.h {
                    maxDim = (dims.width, dims.height)
                }
                for range in format.videoSupportedFrameRateRanges {
                    maxFPS = max(maxFPS, range.maxFrameRate)
                }
            }
            // 光圈与视场角（真机可用）
            let aperture = device.lensAperture
            let fov = device.activeFormat.videoFieldOfView
            var specParts: [String] = ["\(maxDim.w)×\(maxDim.h) @ \(Int(maxFPS))fps"]
            if aperture > 0 {
                let apStr = String(format: "f/%.1f", aperture)
                specParts.append(apStr)
            }
            if fov > 0 {
                specParts.append("视场 \(Int(fov))°")
            }
            if device.isVirtualDevice || device.constituentDevices.count > 1 {
                specParts.append("多摄融合")
            }
            cards.append(MetricCard(
                id: "cam.\(index)", name: "\(lensLabel) (\(position))",
                value: specParts.joined(separator: " · "),
                source: .appleAPI,
                method: "AVCaptureDevice.formats（分辨率/帧率）+ lensAperture（光圈）+ videoFieldOfView（视场角）",
                limitation: device.deviceType == .builtInTrueDepthCamera ? "景深镜头" : nil,
                status: .ok, collectedAt: now, category: .camera
            ))
        }

        return cards
    }
}
