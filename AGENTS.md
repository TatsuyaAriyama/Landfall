# KeelMira iOS delivery rules

- After every change that affects the iOS app, do not stop after editing files or reporting a successful compile.
- Build and verify the latest source for the production iOS target. Treat “production” as the repository's configured signed release channel (for example TestFlight or App Store), not merely a Debug build. If publishing is unavailable because signing, credentials, review, or a release pipeline is missing, report the exact blocker and never claim production was updated.
- Build the same latest source for the currently booted iOS Simulator, terminate the installed app, install the new `.app` with `simctl install`, relaunch it, and verify the changed screen or behavior in the Simulator UI.
- Never build or install the Simulator app with `CODE_SIGNING_ALLOWED=NO`. Firebase Auth Keychain access requires the app's ad-hoc code-signing identifier to equal `com.tatsuyaariyama.Landfall`; an unsigned build is a sign-in outage. Use `Tools/install_signed_simulators.sh`, which refuses to install an app whose signature identifier does not match its bundle identifier.
- Preserve the Simulator's app data when replacing the bundle unless the task explicitly requires a clean install.
- In the final response, state separately what was verified for the production iOS target and what was installed and verified in Simulator.
- At a coherent checkpoint after each completed work item, inspect the mixed worktree, commit only the files that belong to that checkpoint, and push the current branch to GitHub. Never sweep unrelated user changes into the commit.

## Home Island visual language

- Use translucent white glass as the default surface for persistent Home Island HUD elements, with deep harbor-green text and icons for contrast.
- Use the app's readable system typography through `LFFont.copy` for primary text and `LFFont.label` for secondary guidance. Do not introduce decorative display type into functional UI.
- Start new Home Island feature cards with `LFHomeFeatureStyle` and `.lfHomeFeatureCard()` so new functionality inherits the established surface, ink, outline, and typography instead of defining another visual language.
- New Home Island controls, player-facing cards, compact status surfaces, and navigation items should extend this visual language unless a distinct mode (such as photography or a destructive confirmation) has a clear functional reason to differ.
