import AVFoundation
import Contacts
import CoreLocation
import EventKit
import Foundation
import Photos
import UIKit

/// 隐私与权限状态采集器：只读查询各框架授权状态，不触发弹窗、不采集敏感数据
public final class PrivacyProvider: @unchecked Sendable {
    public let category: MetricCategory = .privacy

    public init() {}

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()

        // 相机
        cards.append(avCard(
            id: "priv.camera", name: "相机",
            status: AVCaptureDevice.authorizationStatus(for: .video),
            method: "AVCaptureDevice.authorizationStatus(for: .video)", now: now
        ))
        // 麦克风
        cards.append(avCard(
            id: "priv.mic", name: "麦克风",
            status: AVCaptureDevice.authorizationStatus(for: .audio),
            method: "AVCaptureDevice.authorizationStatus(for: .audio)", now: now
        ))
        // 照片
        cards.append(photoCard(now: now))
        // 位置
        cards.append(locationCard(now: now))
        // 通讯录
        cards.append(permCard(
            id: "priv.contacts", name: "通讯录",
            text: cnText(CNContactStore.authorizationStatus(for: .contacts)),
            status: cnStatus(CNContactStore.authorizationStatus(for: .contacts)),
            method: "CNContactStore.authorizationStatus(for: .contacts)", now: now
        ))
        // 日历与提醒
        if #available(iOS 17.0, *) {
            cards.append(permCard(
                id: "priv.calendar", name: "日历",
                text: ekText(EKEventStore.authorizationStatus(for: .event)),
                status: ekStatus(EKEventStore.authorizationStatus(for: .event)),
                method: "EKEventStore.authorizationStatus(for: .event)", now: now
            ))
            cards.append(permCard(
                id: "priv.reminders", name: "提醒事项",
                text: ekText(EKEventStore.authorizationStatus(for: .reminder)),
                status: ekStatus(EKEventStore.authorizationStatus(for: .reminder)),
                method: "EKEventStore.authorizationStatus(for: .reminder)", now: now
            ))
        } else {
            cards.append(permCard(
                id: "priv.calendar", name: "日历 / 提醒事项",
                text: ekText(EKEventStore.authorizationStatus(for: .event)),
                status: ekStatus(EKEventStore.authorizationStatus(for: .event)),
                method: "EKEventStore.authorizationStatus(for: .event)", now: now
            ))
        }

        // 本地化信息（无权限要求的系统可见信息）
        let locale = Locale.current
        cards.append(MetricCard(
            id: "priv.lang", name: "首选语言", value: Locale.preferredLanguages.first ?? "unknown",
            source: .appleAPI, method: "Locale.preferredLanguages", status: .ok,
            collectedAt: now, category: .privacy
        ))
        let regionName = locale.region.flatMap {
            locale.localizedString(forRegionCode: $0.identifier)
        } ?? locale.identifier
        cards.append(MetricCard(
            id: "priv.region", name: "地区", value: regionName,
            source: .appleAPI, method: "Locale.region + localizedString(forRegionCode:)",
            status: .ok, collectedAt: now, category: .privacy
        ))
        cards.append(MetricCard(
            id: "priv.timezone", name: "时区", value: TimeZone.current.identifier,
            source: .appleAPI, method: "TimeZone.current.identifier", status: .ok,
            collectedAt: now, category: .privacy
        ))
        cards.append(MetricCard(
            id: "priv.calendarid", name: "日历类型", value: "\(locale.calendar.identifier)",
            source: .appleAPI, method: "Locale.calendar.identifier", status: .ok,
            collectedAt: now, category: .privacy
        ))
        cards.append(MetricCard(
            id: "priv.12h", name: "24 小时制", value: DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)?.contains("a") == true ? "关（12 小时制）" : "开（24 小时制）",
            source: .derived, method: "Locale dateFormat 模板 'j' 检查", status: .ok,
            collectedAt: now, category: .privacy
        ))

        // IFV（App 专属标识符，用户可重置）
        if let ifv = UIDevice.current.identifierForVendor?.uuidString {
            cards.append(MetricCard(
                id: "priv.ifv", name: "供应商标识 (IDFV)", value: ifv,
                source: .appleAPI, method: "UIDevice.identifierForVendor",
                limitation: "同一开发者所有 App 共享；全部卸载后改变",
                status: .ok, collectedAt: now, category: .privacy
            ))
        }

        return cards
    }

    private func permCard(id: String, name: String, text: String, status: MetricStatus, method: String, now: Date) -> MetricCard {
        MetricCard(
            id: id, name: name, value: text,
            source: .appleAPI, method: method,
            limitation: status == .unauthorized ? "可在 设置 → 隐私与安全性 中修改" : nil,
            status: status, collectedAt: now, category: .privacy
        )
    }

    private func avCard(id: String, name: String, status: AVAuthorizationStatus, method: String, now: Date) -> MetricCard {
        let (text, cardStatus): (String, MetricStatus) = {
            switch status {
            case .authorized: return ("已授权", .ok)
            case .denied: return ("已拒绝", .unauthorized)
            case .restricted: return ("受限", .unauthorized)
            case .notDetermined: return ("未请求", .degraded)
            @unknown default: return ("未知", .degraded)
            }
        }()
        return permCard(id: id, name: name, text: text, status: cardStatus, method: method, now: now)
    }

    // 注意：EKAuthorizationStatus 的 denied(1)/restricted(2) 顺序与 AV/CN 相反，必须独立 switch
    private func ekText(_ s: EKAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "已授权"
        case .denied: return "已拒绝"
        case .restricted: return "受限"
        case .notDetermined: return "未请求"
        @unknown default: return "未知"
        }
    }
    private func ekStatus(_ s: EKAuthorizationStatus) -> MetricStatus {
        switch s {
        case .authorized: return .ok
        case .denied, .restricted: return .unauthorized
        case .notDetermined: return .degraded
        @unknown default: return .degraded
        }
    }

    private func cnText(_ s: CNAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "已授权"
        case .denied: return "已拒绝"
        case .restricted: return "受限"
        case .limited: return "受限访问"
        case .notDetermined: return "未请求"
        @unknown default: return "未知"
        }
    }
    private func cnStatus(_ s: CNAuthorizationStatus) -> MetricStatus {
        switch s {
        case .authorized: return .ok
        case .denied, .restricted: return .unauthorized
        case .limited: return .degraded
        case .notDetermined: return .degraded
        @unknown default: return .degraded
        }
    }

    private func photoCard(now: Date) -> MetricCard {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let (text, cardStatus): (String, MetricStatus) = {
            switch status {
            case .authorized: return ("完全访问", .ok)
            case .limited: return ("受限访问", .degraded)
            case .denied: return ("已拒绝", .unauthorized)
            case .restricted: return ("受限", .unauthorized)
            case .notDetermined: return ("未请求", .degraded)
            @unknown default: return ("未知", .degraded)
            }
        }()
        return MetricCard(
            id: "priv.photos", name: "照片", value: text,
            source: .appleAPI, method: "PHPhotoLibrary.authorizationStatus(for: .readWrite)",
            limitation: cardStatus == .unauthorized ? "可在 设置 → 隐私与安全性 → 照片 中修改" : nil,
            status: cardStatus, collectedAt: now, category: .privacy
        )
    }

    private func locationCard(now: Date) -> MetricCard {
        let status = CLLocationManager.authorizationStatus()
        let (text, cardStatus): (String, MetricStatus) = {
            switch status {
            case .authorizedAlways: return ("始终", .ok)
            case .authorizedWhenInUse: return ("使用期间", .ok)
            case .denied: return ("已拒绝", .unauthorized)
            case .restricted: return ("受限", .unauthorized)
            case .notDetermined: return ("未请求", .degraded)
            @unknown default: return ("未知", .degraded)
            }
        }()
        return MetricCard(
            id: "priv.location", name: "定位", value: text,
            source: .appleAPI, method: "CLLocationManager.authorizationStatus()",
            limitation: cardStatus == .unauthorized ? "可在 设置 → 隐私与安全性 → 定位服务 中修改" : nil,
            status: cardStatus, collectedAt: now, category: .privacy
        )
    }
}
