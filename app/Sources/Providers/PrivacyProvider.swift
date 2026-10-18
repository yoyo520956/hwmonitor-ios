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
        cards.append(permCard(
            id: "priv.camera", name: "Camera",
            status: AVCaptureDevice.authorizationStatus(for: .video),
            method: "AVCaptureDevice.authorizationStatus(for: .video)", now: now
        ))
        // 麦克风
        cards.append(permCard(
            id: "priv.mic", name: "Microphone",
            status: AVCaptureDevice.authorizationStatus(for: .audio),
            method: "AVCaptureDevice.authorizationStatus(for: .audio)", now: now
        ))
        // 照片
        cards.append(photoCard(now: now))
        // 位置
        cards.append(locationCard(now: now))
        // 通讯录
        cards.append(permCard(
            id: "priv.contacts", name: "Contacts",
            status: CNContactStore.authorizationStatus(for: .contacts),
            method: "CNContactStore.authorizationStatus(for: .contacts)", now: now
        ))
        // 日历与提醒
        if #available(iOS 17.0, *) {
            cards.append(permCard(
                id: "priv.calendar", name: "Calendar",
                status: EKEventStore.authorizationStatus(for: .event),
                method: "EKEventStore.authorizationStatus(for: .event)", now: now
            ))
            cards.append(permCard(
                id: "priv.reminders", name: "Reminders",
                status: EKEventStore.authorizationStatus(for: .reminder),
                method: "EKEventStore.authorizationStatus(for: .reminder)", now: now
            ))
        } else {
            cards.append(permCard(
                id: "priv.calendar", name: "Calendar / Reminders",
                status: EKEventStore.authorizationStatus(for: .event),
                method: "EKEventStore.authorizationStatus(for: .event)", now: now
            ))
        }

        // 本地化信息（无权限要求的系统可见信息）
        let locale = Locale.current
        cards.append(MetricCard(
            id: "priv.lang", name: "Preferred Language", value: Locale.preferredLanguages.first ?? "unknown",
            source: .appleAPI, method: "Locale.preferredLanguages", status: .ok,
            collectedAt: now, category: .privacy
        ))
        cards.append(MetricCard(
            id: "priv.region", name: "Region", value: locale.region?.displayName ?? locale.identifier,
            source: .appleAPI, method: "Locale.region", status: .ok,
            collectedAt: now, category: .privacy
        ))
        cards.append(MetricCard(
            id: "priv.timezone", name: "Time Zone", value: TimeZone.current.identifier,
            source: .appleAPI, method: "TimeZone.current.identifier", status: .ok,
            collectedAt: now, category: .privacy
        ))
        cards.append(MetricCard(
            id: "priv.calendarid", name: "Calendar Identifier", value: locale.calendar.identifier.rawValue,
            source: .appleAPI, method: "Locale.calendar.identifier", status: .ok,
            collectedAt: now, category: .privacy
        ))
        cards.append(MetricCard(
            id: "priv.12h", name: "24-hour Time", value: DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)?.contains("a") == true ? "Off (12-hour)" : "On (24-hour)",
            source: .derived, method: "Locale dateFormat template 'j' inspection", status: .ok,
            collectedAt: now, category: .privacy
        ))

        // IFV（App 专属标识符，用户可重置）
        if let ifv = UIDevice.current.identifierForVendor?.uuidString {
            cards.append(MetricCard(
                id: "priv.ifv", name: "Identifier for Vendor", value: ifv,
                source: .appleAPI, method: "UIDevice.identifierForVendor",
                limitation: "Same across apps from one vendor; changes if all vendor apps are removed",
                status: .ok, collectedAt: now, category: .privacy
            ))
        }

        return cards
    }

    private func permCard(id: String, name: String, status: AVAuthorizationStatus, method: String, now: Date) -> MetricCard {
        let (text, cardStatus): (String, MetricStatus) = {
            switch status {
            case .authorized: return ("Authorized", .ok)
            case .denied: return ("Denied", .unauthorized)
            case .restricted: return ("Restricted", .unauthorized)
            case .notDetermined: return ("Not Requested", .degraded)
            @unknown default: return ("Unknown", .degraded)
            }
        }()
        return MetricCard(
            id: id, name: name, value: text,
            source: .appleAPI, method: method,
            limitation: cardStatus == .unauthorized ? "Change in Settings → Privacy & Security" : nil,
            status: cardStatus, collectedAt: now, category: .privacy
        )
    }

    private func photoCard(now: Date) -> MetricCard {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let (text, cardStatus): (String, MetricStatus) = {
            switch status {
            case .authorized: return ("Full Access", .ok)
            case .limited: return ("Limited", .degraded)
            case .denied: return ("Denied", .unauthorized)
            case .restricted: return ("Restricted", .unauthorized)
            case .notDetermined: return ("Not Requested", .degraded)
            case .addOnly: return ("Add Only", .degraded)
            @unknown default: return ("Unknown", .degraded)
            }
        }()
        return MetricCard(
            id: "priv.photos", name: "Photos", value: text,
            source: .appleAPI, method: "PHPhotoLibrary.authorizationStatus(for: .readWrite)",
            limitation: cardStatus == .unauthorized ? "Change in Settings → Privacy & Security → Photos" : nil,
            status: cardStatus, collectedAt: now, category: .privacy
        )
    }

    private func locationCard(now: Date) -> MetricCard {
        let status = CLLocationManager.authorizationStatus()
        let (text, cardStatus): (String, MetricStatus) = {
            switch status {
            case .authorizedAlways: return ("Always", .ok)
            case .authorizedWhenInUse: return ("While Using", .ok)
            case .denied: return ("Denied", .unauthorized)
            case .restricted: return ("Restricted", .unauthorized)
            case .notDetermined: return ("Not Requested", .degraded)
            @unknown default: return ("Unknown", .degraded)
            }
        }()
        return MetricCard(
            id: "priv.location", name: "Location", value: text,
            source: .appleAPI, method: "CLLocationManager.authorizationStatus()",
            limitation: cardStatus == .unauthorized ? "Change in Settings → Privacy & Security → Location Services" : nil,
            status: cardStatus, collectedAt: now, category: .privacy
        )
    }
}
