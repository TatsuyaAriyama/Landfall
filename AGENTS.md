# KeelMira iOS delivery rules

- After every change that affects the iOS app, do not stop after editing files or reporting a successful compile.
- Build and verify the latest source for the production iOS target. Treat “production” as the repository's configured signed release channel (for example TestFlight or App Store), not merely a Debug build. If publishing is unavailable because signing, credentials, review, or a release pipeline is missing, report the exact blocker and never claim production was updated.
- Build the same latest source for the currently booted iOS Simulator, terminate the installed app, install the new `.app` with `simctl install`, relaunch it, and verify the changed screen or behavior in the Simulator UI.
- Preserve the Simulator's app data when replacing the bundle unless the task explicitly requires a clean install.
- In the final response, state separately what was verified for the production iOS target and what was installed and verified in Simulator.
- At a coherent checkpoint after each completed work item, inspect the mixed worktree, commit only the files that belong to that checkpoint, and push the current branch to GitHub. Never sweep unrelated user changes into the commit.

## Home Island visual language

- Use translucent white glass as the default surface for persistent Home Island HUD elements, with deep harbor-green text and icons for contrast.
- New Home Island controls, player-facing cards, compact status surfaces, and navigation items should extend this visual language unless a distinct mode (such as photography or a destructive confirmation) has a clear functional reason to differ.
