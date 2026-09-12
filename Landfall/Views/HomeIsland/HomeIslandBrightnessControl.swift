import SwiftUI

/// The same saved setting in Settings and over the live island. Keeping this
/// control on the island lets the player judge the result before closing it.
struct HomeIslandBrightnessControl: View {
    @Binding var token: String
    var ink: Color = LFHomeFeatureStyle.ink

    private var selected: HomeIslandBrightness { .resolve(token) }

    private var step: Binding<Double> {
        Binding(
            get: { Double(selected.step) },
            set: { value in
                let index = min(4, max(0, Int(value.rounded()) - 1))
                let next = HomeIslandBrightness.allCases[index]
                guard next != selected else { return }
                token = next.rawValue
                Haptics.tap(.light)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(selected.label)
                    .font(LFFont.copy(15))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    token = HomeIslandBrightness.standard.rawValue
                    Haptics.tap(.light)
                } label: {
                    Text("Standard")
                        .font(LFFont.label(12))
                        .padding(.horizontal, 10)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(selected == .standard)
                .opacity(selected == .standard ? 0.4 : 1)
                .accessibilityLabel(Text("Reset island brightness"))
            }

            HStack(spacing: 12) {
                Image(systemName: "sun.min")
                    .accessibilityHidden(true)
                Slider(value: step, in: 1...5, step: 1) {
                    Text("Island brightness")
                }
                .tint(ink)
                .accessibilityValue(Text(selected.label))
                Image(systemName: "sun.max.fill")
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)

            Text("Your island stays in daylight. This setting keeps your preferred brightness outdoors and indoors.")
                .font(LFFont.label(12))
                .foregroundStyle(ink.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ink)
    }
}
