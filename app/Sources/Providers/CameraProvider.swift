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
                id: "cam.count", name: "Cameras", value: "0",
                source: .appleAPI, method: "AVCaptureDevice.DiscoverySession(.video)",
                limitation: "No cameras discovered (simulator or restricted device)",
                status: .unavailable, collectedAt: now, category: .camera
            ))
            return cards
        }

        cards.append(MetricCard(
            id: "cam.count", name: "Cameras Found", value: "\(devices.count)",
            numeric: Double(devices.count), unit: "lenses",
            source: .appleAPI, method: "AVCaptureDevice.DiscoverySession(.video, position: .unspecified)",
            status: .ok, collectedAt: now, category: .camera
        ))

        for (index, device) in devices.prefix(6).enumerated() {
            let position: String
            switch device.position {
            case .back: position = "Back"
            case .front: position = "Front"
            default: position = "Unknown"
            }
            let lensLabel = device.deviceType == .builtInTrueDepthCamera
                ? "TrueDepth" : "Lens \(index + 1)"

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
            cards.append(MetricCard(
                id: "cam.\(index)", name: "\(lensLabel) (\(position))",
                value: "\(maxDim.w)×\(maxDim.h) @ \(Int(maxFPS))fps",
                source: .appleAPI,
                method: "AVCaptureDevice.formats → CMVideoFormatDescription dimensions + frame rate ranges",
                limitation: device.deviceType == .builtInTrueDepthCamera ? "Depth camera" : nil,
                status: .ok, collectedAt: now, category: .camera
            ))
        }

        return cards
    }
}
