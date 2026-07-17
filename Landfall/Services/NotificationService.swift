import Foundation
import UserNotifications

/// そっと戻れる通知。
///
/// 思想: 煽らない・急かさない・比べない。連続日数や「やっていない」ことには一切触れない。
/// これは *要求* ではなく *招待* — 港はいつでも開いている、という声かけだけを届ける。
/// 既定はオフ。ユーザーが自分で選んだときだけ、選んだ時刻に静かに一度鳴る。
/// その日にもう記録していれば、今日のぶんは黙って取り下げる(来た人をつつかない)。
enum NotificationService {
    static let enabledKey = "notifyEnabled"
    static let hourKey = "notifyHour"      // 0-23、既定 21
    static let minuteKey = "notifyMinute"  // 0-59、既定 0
    private static let idPrefix = "landfall.gentle."
    private static let horizonDays = 14    // 先の日数ぶんだけ積んでおき、起動のたびに補充する

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var hour: Int {
        UserDefaults.standard.object(forKey: hourKey) as? Int ?? 21
    }
    static var minute: Int {
        UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 0
    }

    // やさしい声かけ。ローテーションで単調さと圧を避ける。(タイトル, 本文)
    private static let linesJA: [(String, String)] = [
        ("港は、いつでもここにある。", "戻りたくなったら、いつでもどうぞ。"),
        ("今日はどんな一日でしたか。", "少しだけでも、寄っていきませんか。"),
        ("休んだ日も、航海のうち。", "また風が吹いたら、進めばいい。"),
        ("おかえりを、待っています。", "焦らなくて、大丈夫。"),
        ("ひと呼吸、置いていく場所。", "気が向いたら、開いてみて。"),
    ]
    private static let linesEN: [(String, String)] = [
        ("The harbor is always here.", "Come back whenever you like."),
        ("How was your day?", "Stop by for a moment, if you want."),
        ("Rest days are part of the voyage.", "Sail on when the wind returns."),
        ("Welcome back, whenever.", "No need to rush."),
        ("A quiet place to pause.", "Open it if you feel like it."),
    ]

    private static var lines: [(String, String)] {
        switch AppLanguage.current {
        case .ja: return linesJA
        case .en: return linesEN
        case .system:
            let langs = Locale.preferredLanguages
            return (langs.first?.hasPrefix("ja") ?? false) ? linesJA : linesEN
        }
    }

    /// 設定トグルをオンにしたとき。許可を求め、許可されれば有効化＋スケジュール。
    /// 拒否されたら有効フラグを戻す(トグルは実状態に合わせる)。返り値=最終的に有効か。
    @MainActor
    static func enable(recordedToday: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        if granted {
            await reschedule(recordedToday: recordedToday)
        }
        return granted
    }

    /// 設定トグルをオフにしたとき。保留中の声かけをすべて取り下げる。
    @MainActor
    static func disable() async {
        UserDefaults.standard.set(false, forKey: enabledKey)
        await removeAllPending()
    }

    /// 起動時・時刻変更時・記録時に呼ぶ。有効なら先の日数ぶんを積み直す。
    /// recordedToday が true なら今日のぶんは積まない(来てくれた人を今日はつつかない)。
    @MainActor
    static func reschedule(recordedToday: Bool) async {
        guard isEnabled else { await removeAllPending(); return }
        let center = UNUserNotificationCenter.current()
        // 未許可に変わっていたら黙って降りる。
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        await removeAllPending()

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let picked = lines

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = minute
            guard let fireDate = calendar.date(from: comps) else { continue }
            // 過ぎた時刻は積まない。今日ぶんは、もう記録済みなら飛ばす。
            if fireDate <= now { continue }
            if offset == 0 && recordedToday { continue }

            let line = picked[offset % picked.count]
            let content = UNMutableNotificationContent()
            content.title = line.0
            content.body = line.1
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: "\(idPrefix)\(offset)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    private static func removeAllPending() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
