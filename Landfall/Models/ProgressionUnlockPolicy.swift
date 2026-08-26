import Foundation

/// Level rewards that change the playable Home Island itself.
enum HomeIslandExpansionPolicy {
    static let unlockLevel = 10
    static let baseScale: Float = 1
    /// 12% in each horizontal axis is about 25% more usable area: enough for a
    /// real second district without making existing layouts look abandoned.
    static let expandedScale: Float = 1.12

    static func scale(for playerLevel: Int) -> Float {
        playerLevel >= unlockLevel ? expandedScale : baseScale
    }
}

enum ShipUnlockPolicy {
    enum LockReason: Equatable {
        case level(Int)
        case voyagePass
    }

    static func lockReason(
        requiredLevel: Int,
        requiresVoyagePass: Bool,
        playerLevel: Int,
        hasVoyagePass: Bool,
        alreadySelected: Bool = false
    ) -> LockReason? {
        // A selected level reward is not taken away if edited records lower the
        // level later. Subscription-only ships still fail closed when the pass
        // expires; the saved choice is retained and returns with the pass.
        if requiresVoyagePass && !hasVoyagePass { return .voyagePass }
        if !alreadySelected && playerLevel < requiredLevel { return .level(requiredLevel) }
        return nil
    }
}
