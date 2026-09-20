#!/usr/bin/env python3
"""Exercise reminder races with a controlled center and isolated defaults."""
from pathlib import Path
import subprocess
import tempfile
import sys

repo = Path(__file__).resolve().parents[1]
source = (repo / 'Landfall/Services/NotificationService.swift').read_text()
if '--baseline' in sys.argv:
    source = subprocess.check_output(['git', 'show', 'HEAD:Landfall/Services/NotificationService.swift'], cwd=repo, text=True)
    source = source.replace('    private static func removeAllPending()', '    @MainActor\n    private static func removeAllPending()')
source = source.replace('import UserNotifications', '')
source = source.replace('UserDefaults.standard', 'notificationProbeDefaults')
source = source.replace('let now = Date()', 'let now = notificationProbeNow')
stubs = r'''
import Foundation
let notificationProbeSuite = "landfall.notifications.probe." + UUID().uuidString
let notificationProbeDefaults = UserDefaults(suiteName: notificationProbeSuite)!
let notificationProbeNow = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
enum AppLanguage { case ja, en, system; static let current = AppLanguage.en }
struct UNAuthorizationOptions: OptionSet {
    let rawValue: Int
    static let alert = Self(rawValue: 1)
    static let sound = Self(rawValue: 2)
}
enum UNAuthorizationStatus { case authorized, provisional, denied }
struct UNNotificationSettings { let authorizationStatus: UNAuthorizationStatus }
enum UNNotificationSound { case `default` }
class UNMutableNotificationContent { var title = ""; var body = ""; var sound: UNNotificationSound? }
class UNCalendarNotificationTrigger {
    let dateComponents: DateComponents
    init(dateMatching: DateComponents, repeats: Bool) { dateComponents = dateMatching }
}
class UNNotificationRequest {
    let identifier: String
    let trigger: UNCalendarNotificationTrigger
    init(identifier: String, content: UNMutableNotificationContent, trigger: UNCalendarNotificationTrigger) {
        self.identifier = identifier; self.trigger = trigger
    }
}
// Synchronization is deliberately controlled by the probe, reproducing delayed
// notification-center replies without relying on OS authorization or timing.
@MainActor class UNUserNotificationCenter {
    static let shared = UNUserNotificationCenter()
    static func current() -> UNUserNotificationCenter { shared }
    var requests: [String: UNNotificationRequest] = [:]
    var authorizationStatus = UNAuthorizationStatus.authorized
    var pauseNextAdd = false
    var pauseAuthorization = false
    var addWaiter: CheckedContinuation<Void, Never>?
    var authorizationWaiter: CheckedContinuation<Bool, Never>?
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        if pauseAuthorization { return await withCheckedContinuation { authorizationWaiter = $0 } }
        return authorizationStatus != .denied
    }
    func notificationSettings() async -> UNNotificationSettings { UNNotificationSettings(authorizationStatus: authorizationStatus) }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { Array(requests.values) }
    func removePendingNotificationRequests(withIdentifiers ids: [String]) { for id in ids { requests[id] = nil } }
    func add(_ request: UNNotificationRequest) async throws {
        if pauseNextAdd {
            pauseNextAdd = false
            await withCheckedContinuation { addWaiter = $0 }
        }
        requests[request.identifier] = request
    }
    func resumeAdd() { let waiter = addWaiter; addWaiter = nil; waiter?.resume() }
    func resumeAuthorization() { let waiter = authorizationWaiter; authorizationWaiter = nil; pauseAuthorization = false; waiter?.resume(returning: true) }
}
@main struct NotificationProbe {
    @MainActor static func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<100000 { if predicate() { return }; await Task.yield() }
        fatalError("probe did not reach expected suspension")
    }
    @MainActor static func main() async {
        defer { notificationProbeDefaults.removePersistentDomain(forName: notificationProbeSuite) }
        let center = UNUserNotificationCenter.shared
        let unrelated = UNNotificationRequest(identifier: "unrelated", content: UNMutableNotificationContent(), trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(), repeats: false))
        center.requests[unrelated.identifier] = unrelated
        notificationProbeDefaults.set(true, forKey: NotificationService.enabledKey)
        notificationProbeDefaults.set(21, forKey: NotificationService.hourKey)
        center.pauseNextAdd = true
        let initial = Task { await NotificationService.reschedule(recordedToday: false) }
        await waitUntil { center.addWaiter != nil }
        let disable = Task { await NotificationService.disable() }
        await waitUntil { !NotificationService.isEnabled }
        center.resumeAdd()
        await initial.value; await disable.value
        precondition(Set(center.requests.keys) == ["unrelated"], "disable must remove an in-flight reminder and preserve unrelated requests")
        print("PASS: disable during an in-flight add")

        notificationProbeDefaults.set(true, forKey: NotificationService.enabledKey)
        center.pauseNextAdd = true
        let beforeRecord = Task { await NotificationService.reschedule(recordedToday: false) }
        await waitUntil { center.addWaiter != nil }
        var recordStarted = false
        let afterRecord = Task { recordStarted = true; await NotificationService.reschedule(recordedToday: true) }
        await waitUntil { recordStarted }
        center.resumeAdd()
        await beforeRecord.value; await afterRecord.value
        precondition(center.requests["landfall.gentle.0"] == nil, "recording today must remove today's in-flight reminder")
        precondition(center.requests.count == 14, "13 future reminders plus unrelated request")
        print("PASS: recorded-today refresh during an in-flight add")

        center.pauseNextAdd = true
        let oldTime = Task { await NotificationService.reschedule(recordedToday: false) }
        await waitUntil { center.addWaiter != nil }
        notificationProbeDefaults.set(22, forKey: NotificationService.hourKey)
        var timeStarted = false
        let newTime = Task { timeStarted = true; await NotificationService.reschedule(recordedToday: false) }
        await waitUntil { timeStarted }
        center.resumeAdd()
        await oldTime.value; await newTime.value
        let reminders = center.requests.values.filter { $0.identifier.hasPrefix("landfall.gentle.") }
        precondition(reminders.count == 14 && reminders.allSatisfy { $0.trigger.dateComponents.hour == 22 }, "latest chosen time must apply to every reminder")
        print("PASS: time change replaces all stale reminder times")

        center.authorizationStatus = .denied
        await NotificationService.reschedule(recordedToday: false)
        precondition(Set(center.requests.keys) == ["unrelated"], "revoked permission must remove pending app reminders")
        print("PASS: permission revocation clears app reminders")

        await NotificationService.disable()
        center.authorizationStatus = .authorized
        center.pauseAuthorization = true
        let enabling = Task { await NotificationService.enable(recordedToday: false) }
        await waitUntil { center.authorizationWaiter != nil }
        await NotificationService.disable()
        center.resumeAuthorization()
        let enabled = await enabling.value
        precondition(!enabled && !NotificationService.isEnabled && Set(center.requests.keys) == ["unrelated"], "late permission reply must not undo disable")
        print("PASS: disable during authorization remains disabled")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='landfall-notification-probe-') as temp:
    path = Path(temp)
    (path / 'NotificationService.swift').write_text(source)
    (path / 'Probe.swift').write_text(stubs)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', str(path / 'NotificationService.swift'), str(path / 'Probe.swift'), '-o', str(path / 'probe')], check=True)
    subprocess.run([str(path / 'probe')], check=True, timeout=30)
