import Foundation

/// A player's level is derived from the canonical work-session history.
/// Derivation avoids a second mutable XP balance that could drift from edited,
/// deleted, or newly synced sessions.
struct PlayerLevelProgress: Equatable {
    static let minutesPerLevel = 10 * 60

    let totalMinutes: Int

    init(totalMinutes: Int) {
        self.totalMinutes = max(0, totalMinutes)
    }

    init(sessions: [StudySession]) {
        self.init(totalMinutes: sessions.reduce(0) { total, session in
            total + max(0, session.minutes)
        })
    }

    var level: Int {
        totalMinutes / Self.minutesPerLevel + 1
    }

    var minutesIntoLevel: Int {
        totalMinutes % Self.minutesPerLevel
    }

    var minutesToNextLevel: Int {
        Self.minutesPerLevel - minutesIntoLevel
    }

    var fractionToNextLevel: Double {
        Double(minutesIntoLevel) / Double(Self.minutesPerLevel)
    }

    func unlocks(requiredLevel: Int) -> Bool {
        level >= requiredLevel
    }
}
