# Wrapped share cards (PNG)

App Store screenshot / ad creative renders of the 4 Wrapped cards
(`Landfall/Views/Wrapped/WrappedCard{1..4}*.swift`), using the dummy month
(`WrappedMonth.dummy`: 14 studied / 17 rested days, 6-day longest gap,
4 returns, Phoenix type).

| File | Card |
| --- | --- |
| `Landfall-2026-05-card1-fact.png` | The facts — studied vs. rested days |
| `Landfall-2026-05-card2-silence.png` | The story of the longest gap |
| `Landfall-2026-05-card3-archetype.png` | Comeback type (Phoenix) |
| `Landfall-2026-05-card4-trace.png` | Full-month trace |

1170×2079px (390×693pt @3x), transparent rounded corners — same export
scale as the in-app Share button (`Landfall/Views/Wrapped/WrappedShare.swift`).

## How these were made

This dev environment has no Xcode/SwiftUI, so these are not exported from
the app. They're a from-scratch HTML/CSS/SVG re-implementation of the same
views, built off the exact design tokens in `Landfall/Design/Theme.swift`
and the same layout/derivation logic in `WrappedMonth.swift` and
`MonthWaveform.swift`, rendered with headless Chromium at 3x. The system
font (Liberation Sans) stands in for San Francisco, which isn't installed
on Linux — everything else (colors, sizes, spacing, geometry) matches the
Swift source.

Regenerate with:

```
cd Tools/CardPNGRenderer
npm install --no-save playwright
node render-wrapped-cards.js ../../Marketing/WrappedCards
```

For pixel-perfect output with the real SF font, prefer either the app's
own Share button on a Wrapped card, or `Tools/RenderHarness/RenderCard.swift`
on macOS.
