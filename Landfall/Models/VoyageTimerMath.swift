import Foundation

/// Corrupt or partially-cleared timer defaults must never become a Unix-epoch
/// duration on screen. Keep all floating-point validation before Int conversion.
enum VoyageTimerMath {
    /// Longer than the product's maximum creditable session, while still
    /// leaving room for a multi-day voyage to recover after an app restart.
    private static let maximumRecoverableDuration: Double = 7 * 24 * 60 * 60

    static func isActive(
        startedAt: Double,
        itemID: String,
        at date: Date = Date()
    ) -> Bool {
        let now = date.timeIntervalSince1970
        return now.isFinite
            && startedAt.isFinite
            && startedAt > 0
            && startedAt <= now
            && now - startedAt <= maximumRecoverableDuration
            && !itemID.isEmpty
    }

    static func elapsedSeconds(
        startedAt: Double,
        breakSeconds: Double,
        breakStartedAt: Double,
        at date: Date = Date()
    ) -> Int {
        let now = date.timeIntervalSince1970
        guard now.isFinite,
              startedAt.isFinite,
              startedAt > 0,
              startedAt <= now,
              now - startedAt <= maximumRecoverableDuration
        else { return 0 }

        let wallElapsed = max(0, now - startedAt)
        let accumulatedBreak = breakSeconds.isFinite
            ? min(wallElapsed, max(0, breakSeconds))
            : 0
        let activeBreak: Double
        if breakStartedAt.isFinite,
           breakStartedAt >= startedAt,
           breakStartedAt <= now {
            activeBreak = min(
                max(0, wallElapsed - accumulatedBreak),
                max(0, now - breakStartedAt)
            )
        } else {
            activeBreak = 0
        }

        let elapsed = max(0, wallElapsed - accumulatedBreak - activeBreak)
        guard elapsed.isFinite, elapsed < Double(Int.max) else { return 0 }
        return Int(elapsed)
    }

    static func clampedAnchor(_ value: Double, elapsed: Int) -> Int {
        guard value.isFinite else { return 0 }
        return min(elapsed, max(0, Int(min(value, Double(Int.max - 1)))))
    }
}
