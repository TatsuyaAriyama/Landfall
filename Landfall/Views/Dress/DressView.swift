import SwiftUI
import SwiftData

/// 装い。夜の海に浮かぶ自分の船を3Dで眺めながら、帆と船体の色を着せ替える。
/// 色は累計時間で解放される(Web BoatStudio 相当)。
struct DressView: View {
    @Query private var sessions: [StudySession]
    /// 色を選ぶたびに +1 して、3Dの色と選択枠を更新する。
    @State private var version = 0

    private var totalMinutes: Int { totalStudyMinutes(sessions) }

    var body: some View {
        NavigationStack {
            ZStack {
                LFColor.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Your boat")
                            .font(LFFont.copy(26))
                            .foregroundStyle(LFColor.ink)
                            .padding(.top, 32)
                            .padding(.horizontal, 24)

                        BoatSceneView(parts: BoatCustomization.currentParts)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                        Text("Drag to look around.")
                            .font(LFFont.label(13))
                            .foregroundStyle(LFColor.ink.opacity(0.5))
                            .padding(.horizontal, 24)
                            .padding(.top, 12)

                        Text("Voyage so far: \(LF.duration(minutes: totalMinutes))")
                            .font(LFFont.copy(15))
                            .foregroundStyle(LFColor.ink.opacity(0.7))
                            .padding(.horizontal, 24)
                            .padding(.top, 4)

                        ForEach(BoatPart.allCases) { part in
                            partSection(part)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func partSection(_ part: BoatPart) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(part.title)
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.5))
                .padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(part.options) { option in
                        swatch(part, option)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, 20)
    }

    private func swatch(_ part: BoatPart, _ option: BoatOption) -> some View {
        let unlocked = option.isUnlocked(totalMinutes: totalMinutes)
        let selected = BoatCustomization.selectedID(part) == option.id
        return Button {
            guard unlocked else { return }
            BoatCustomization.select(part, option.id)
            Haptics.tap(.light)
            version += 1
        } label: {
            Circle()
                .fill(option.color)
                .frame(width: 44, height: 44)
                .opacity(unlocked ? 1 : 0.3)
                .overlay(Circle().strokeBorder(LFColor.returnOrange, lineWidth: selected ? 3 : 0))
                .overlay {
                    if !unlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(LFColor.inkFixed.opacity(0.5))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(Text(option.id))
    }
}
