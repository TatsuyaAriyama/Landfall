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
        return hasRecoverableStart(startedAt, now: now)
            && !itemID.isEmpty
    }

    static func isResting(
        startedAt: Double,
        breakStartedAt: Double,
        at date: Date = Date()
    ) -> Bool {
        let now = date.timeIntervalSince1970
        return hasRecoverableStart(startedAt, now: now)
            && breakStartedAt.isFinite
            && breakStartedAt >= startedAt
            && breakStartedAt <= now
    }

    static func sanitizedBreakSeconds(
        _ value: Double,
        startedAt: Double,
        at date: Date = Date()
    ) -> Double {
        let now = date.timeIntervalSince1970
        guard hasRecoverableStart(startedAt, now: now), value.isFinite else { return 0 }
        return min(max(0, now - startedAt), max(0, value))
    }

    static func elapsedSeconds(
        startedAt: Double,
        breakSeconds: Double,
        breakStartedAt: Double,
        at date: Date = Date()
    ) -> Int {
        let now = date.timeIntervalSince1970
        guard hasRecoverableStart(startedAt, now: now) else { return 0 }

        let wallElapsed = max(0, now - startedAt)
        let accumulatedBreak = sanitizedBreakSeconds(
            breakSeconds,
            startedAt: startedAt,
            at: date
        )
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

    private static func hasRecoverableStart(_ startedAt: Double, now: Double) -> Bool {
        now.isFinite
            && startedAt.isFinite
            && startedAt > 0
            && startedAt <= now
            && now - startedAt <= maximumRecoverableDuration
    }
}
