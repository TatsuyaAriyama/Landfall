import Foundation

private enum ProbeFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message): message
        }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ProbeFailure.assertion(message) }
}

@main
private enum ProgressionUnlockProbe {
    static func main() throws {
        let levelNineScale = HomeIslandExpansionPolicy.scale(for: 9)
        let levelTenScale = HomeIslandExpansionPolicy.scale(for: 10)
        let expandedAreaRatio = levelTenScale * levelTenScale

        try require(levelNineScale == 1, "the island expanded before level 10")
        try require(levelTenScale == 1.12, "level 10 did not select the designed scale")
        try require(
            (1.20...1.30).contains(expandedAreaRatio),
            "the level 10 island area is not a moderate expansion: \(expandedAreaRatio)"
        )

        try require(
            ShipUnlockPolicy.lockReason(
                requiredLevel: 1,
                requiresVoyagePass: true,
                playerLevel: 99,
                hasVoyagePass: false
            ) == .voyagePass,
            "Garden Estate-style access did not fail closed without Voyage Pass"
        )
        try require(
            ShipUnlockPolicy.lockReason(
                requiredLevel: 1,
                requiresVoyagePass: true,
                playerLevel: 1,
                hasVoyagePass: true
            ) == nil,
            "Voyage Pass did not unlock its exclusive ship"
        )
        try require(
            ShipUnlockPolicy.lockReason(
                requiredLevel: 10,
                requiresVoyagePass: false,
                playerLevel: 9,
                hasVoyagePass: false
            ) == .level(10),
            "the pirate ship unlocked before level 10"
        )
        try require(
            ShipUnlockPolicy.lockReason(
                requiredLevel: 10,
                requiresVoyagePass: false,
                playerLevel: 10,
                hasVoyagePass: false
            ) == nil,
            "the pirate ship remained locked at level 10"
        )
        try require(
            ShipUnlockPolicy.lockReason(
                requiredLevel: 10,
                requiresVoyagePass: false,
                playerLevel: 8,
                hasVoyagePass: false,
                alreadySelected: true
            ) == nil,
            "a previously selected level reward was taken away"
        )
        try require(
            ShipUnlockPolicy.lockReason(
                requiredLevel: 1,
                requiresVoyagePass: true,
                playerLevel: 10,
                hasVoyagePass: false,
                alreadySelected: true
            ) == .voyagePass,
            "an expired pass left its exclusive ship active"
        )

        print("Progression unlock regression probe: PASS")
    }
}
