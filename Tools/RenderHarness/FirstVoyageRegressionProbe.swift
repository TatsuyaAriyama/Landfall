import Foundation

@main
enum FirstVoyageRegressionProbe {
    static func main() {
        routingChecks()
        timerChecks()
        print("FirstVoyageRegressionProbe: PASS")
    }

    private static func routingChecks() {
        let suite = "FirstVoyageRegressionProbe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        precondition(
            FirstVoyageRoutingPolicy.route(
                forceTutorial: false,
                deviceTutorialCompleted: false,
                firebaseUID: "returning-user",
                signedInEntry: .returning,
                canUseDeviceOnlyMode: false,
                defaults: defaults
            ) == .home,
            "A restored Firebase player must return directly to Home."
        )

        precondition(
            FirstVoyageRoutingPolicy.route(
                forceTutorial: false,
                deviceTutorialCompleted: true,
                firebaseUID: "new-user",
                signedInEntry: nil,
                canUseDeviceOnlyMode: false,
                defaults: defaults
            ) == .waitingForAccountClassification,
            "Routing must not guess while interactive sign-in is unresolved."
        )

        FirstVoyageAccountProgress.markTutorialRequired(
            for: "new-user",
            defaults: defaults
        )
        precondition(
            FirstVoyageRoutingPolicy.route(
                forceTutorial: false,
                deviceTutorialCompleted: true,
                firebaseUID: "new-user",
                signedInEntry: .returning,
                canUseDeviceOnlyMode: false,
                defaults: defaults
            ) == .tutorial,
            "An interrupted new-player tutorial must survive relaunch."
        )

        FirstVoyageAccountProgress.markTutorialCompleted(
            for: "new-user",
            defaults: defaults
        )
        precondition(
            FirstVoyageRoutingPolicy.route(
                forceTutorial: false,
                deviceTutorialCompleted: true,
                firebaseUID: "new-user",
                signedInEntry: .newlyCreated,
                canUseDeviceOnlyMode: false,
                defaults: defaults
            ) == .home,
            "A completed first voyage must transition to Home immediately."
        )

        precondition(
            FirstVoyageRoutingPolicy.route(
                forceTutorial: false,
                deviceTutorialCompleted: false,
                firebaseUID: nil,
                signedInEntry: nil,
                canUseDeviceOnlyMode: true,
                defaults: defaults
            ) == .tutorial
        )
    }

    private static func timerChecks() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        precondition(
            VoyageTimerMath.elapsedSeconds(
                startedAt: 0,
                breakSeconds: 0,
                breakStartedAt: 0,
                at: now
            ) == 0,
            "A cleared timer must render zero, not the Unix epoch."
        )
        precondition(
            VoyageTimerMath.elapsedSeconds(
                startedAt: 1_000_100,
                breakSeconds: 0,
                breakStartedAt: 0,
                at: now
            ) == 0,
            "A future timer must be rejected."
        )
        precondition(
            VoyageTimerMath.elapsedSeconds(
                startedAt: 1,
                breakSeconds: 0,
                breakStartedAt: 0,
                at: now
            ) == 0,
            "An ancient timestamp must not become an epoch-sized voyage."
        )
        precondition(
            VoyageTimerMath.elapsedSeconds(
                startedAt: .nan,
                breakSeconds: .infinity,
                breakStartedAt: -.infinity,
                at: now
            ) == 0,
            "Non-finite defaults must not reach Int conversion."
        )
        precondition(
            VoyageTimerMath.elapsedSeconds(
                startedAt: 999_900,
                breakSeconds: 20,
                breakStartedAt: 999_980,
                at: now
            ) == 60,
            "Accumulated and active breaks must both be excluded."
        )
        precondition(VoyageTimerMath.clampedAnchor(.nan, elapsed: 30) == 0)
        precondition(VoyageTimerMath.clampedAnchor(90, elapsed: 30) == 30)
    }
}
