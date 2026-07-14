import SwiftUI

/// カード3「タイプ診断」。背景 midnight、中央揃えの構成。
/// シンボル → タイプ名 → 決め台詞2行 → ピルバッジ。
struct WrappedCard3Archetype: View {
    let month: WrappedMonth

    var body: some View {
        CardScaffold(background: LFColor.midnight) {
            VStack(spacing: 0) {
                CardKicker(text: "あなたの再開力タイプ", color: LFColor.lavender)

                Spacer()

                ArchetypeSymbol(archetype: month.archetype, size: 150)

                Spacer()
                    .frame(height: 40)

                Text(month.archetype.displayName)
                    .font(LFFont.copy(36))
                    .foregroundStyle(.white)

                VStack(spacing: 9) {
                    Text(month.archetype.tagline)
                    Text(month.archetype.subline)
                }
                .font(LFFont.copy(17))
                .foregroundStyle(LFColor.lavender)
                .multilineTextAlignment(.center)
                .padding(.top, 18)

                Spacer()

                HStack(spacing: 12) {
                    if let power = month.resumePower {
                        StatPill(text: "再開力 \(power)")
                    }
                    StatPill(text: "帰還 \(month.resumeCount)回")
                }

                Spacer()
                    .frame(height: 44)

                CardBrandmark(color: .white)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - ピルバッジ

private struct StatPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LFFont.label(14))
            .monospacedDigit()
            .foregroundStyle(LFColor.lavender)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(LFColor.violet, lineWidth: 1.5)
            )
    }
}

#Preview {
    WrappedCard3Archetype(month: .dummy)
}
