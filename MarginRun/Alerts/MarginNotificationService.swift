import Combine
import Foundation
import UserNotifications

@MainActor
final class MarginNotificationService: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private static let sentAlertIDsKey = "alerts.sentAlertIDs"
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
    }

    var canRequestPermission: Bool { authorizationStatus == .notDetermined }
    var notificationsDenied: Bool { authorizationStatus == .denied }

    func refreshAndSync(alerts: [MarginAlert]) async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        sync(alerts: alerts)
    }

    func requestPermissionAndSync(alerts: [MarginAlert]) async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // The status refresh below keeps the UI accurate even if the
            // system request fails.
        }
        await refreshAndSync(alerts: alerts)
    }

    private func sync(alerts: [MarginAlert]) {
        let activeIDs = Set(alerts.map(\.id))
        var sentIDs = Set(defaults.stringArray(forKey: Self.sentAlertIDsKey) ?? [])
        let resolvedIDs = sentIDs.subtracting(activeIDs)

        if !resolvedIDs.isEmpty {
            let notificationIDs = resolvedIDs.map { "margin-alert.\($0)" }
            center.removePendingNotificationRequests(withIdentifiers: notificationIDs)
            center.removeDeliveredNotifications(withIdentifiers: notificationIDs)
            sentIDs.subtract(resolvedIDs)
        }

        for alert in alerts where !sentIDs.contains(alert.id) {
            let content = UNMutableNotificationContent()
            content.title = alert.jobName
            content.body = alert.message
            content.sound = .default
            content.userInfo = ["jobID": alert.jobID.uuidString]

            let request = UNNotificationRequest(
                identifier: "margin-alert.\(alert.id)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            center.add(request)
            sentIDs.insert(alert.id)
        }

        defaults.set(Array(sentIDs), forKey: Self.sentAlertIDsKey)
    }
}
