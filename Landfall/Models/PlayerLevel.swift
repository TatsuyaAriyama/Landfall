import Foundation

/// 作業記録とレベル計算で共有する永続データの上限。
/// UI・同期・Firestore ルールはこの値と `docs/SCHEMA.md` を同じ契約として扱う。
enum WorkRecordPolicy {
    static let maximumSessionMinutes = 6_000
    static let maximumExtraSeconds = 59
    static let maximumSessionNoteCharacters = 500
    static let maximumItemNameCharacters = 60
    static let maximumDayNoteCharacters = 1_000
    static let earliestSupportedDate = Date(timeIntervalSince1970: 946_684_800)
    static let futureClockTolerance: TimeInterval = 10 * 60

    /// 公開プロフィールの既存プロトコルが扱える最大値。無制限の整数をUIや通信へ
    /// 流さず、長期運用時の加算オーバーフローもここで止める。
    static let maximumLevel = 9_999

    static func normalizedNote(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumSessionNoteCharacters))
    }

    static func isValidSession(minutes: Int, extraSeconds: Int) -> Bool {
        (0...maximumSessionMinutes).contains(minutes)
            && (0...maximumExtraSeconds).contains(extraSeconds)
            && (minutes > 0 || extraSeconds > 0)
    }

    static func isValidRecordDate(_ date: Date, now: Date = Date()) -> Bool {
        date >= earliestSupportedDate
            && date <= now.addingTimeInterval(futureClockTolerance)
    }

    static func isValidUpdatedAt(_ date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return true } // v1.0 compatibility
        return isValidRecordDate(date, now: now)
    }
}

/// A player's level is derived from the canonical work-session history.
/// Derivation avoids a second mutable XP balance that could drift from edited,
/// deleted, or newly synced sessions.
struct PlayerLevelProgress: Equatable {
    static let minutesPerLevel = 10 * 60
    static let maximumTrackedMinutes = WorkRecordPolicy.maximumLevel * minutesPerLevel - 1

    let totalMinutes: Int

    init(totalMinutes: Int) {
        self.totalMinutes = min(Self.maximumTrackedMinutes, max(0, totalMinutes))
    }

    init(sessions: [StudySession]) {
        var total = 0
        for session in sessions {
            // 古いストアや改変された同期データに異常値があっても、レベルへは
            // 一切加算しない。正常な長期履歴は上限まで飽和加算する。
            guard WorkRecordPolicy.isValidSession(
                minutes: session.minutes,
                extraSeconds: session.extraSeconds
            ) else { continue }
            total += min(session.minutes, Self.maximumTrackedMinutes - total)
            if total == Self.maximumTrackedMinutes { break }
        }
        self.init(totalMinutes: total)
    }

    var level: Int {
        totalMinutes / Self.minutesPerLevel + 1
    }

    var minutesIntoLevel: Int {
        if level == WorkRecordPolicy.maximumLevel {
            return Self.minutesPerLevel
        }
        return totalMinutes % Self.minutesPerLevel
    }

    var minutesToNextLevel: Int {
        if level == WorkRecordPolicy.maximumLevel {
            return 0
        }
        return Self.minutesPerLevel - minutesIntoLevel
    }

    var fractionToNextLevel: Double {
        if level == WorkRecordPolicy.maximumLevel {
            return 1
        }
        return Double(minutesIntoLevel) / Double(Self.minutesPerLevel)
    }

    func unlocks(requiredLevel: Int) -> Bool {
        level >= requiredLevel
    }
}
