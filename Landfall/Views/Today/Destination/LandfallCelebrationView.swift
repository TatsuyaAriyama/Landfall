import SwiftUI

/// 着岸の一枚。島に到達したとき全画面で出す。目標の種類に関わらず「航海した時間」を添える。
/// Web版 LandfallCelebration 相当。
struct LandfallCelebrationView: View {
    let destination: Destination
    let minutes: Int
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Color(VoyageSceneKit.seaDeep).ignoresSafeArea()
            VoyageSceneView(ratio: 1, steps: [])
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Spacer()
                if minutes > 0 {
                    Text("Work time \(LF.duration(minutes: minutes))")
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.returnOrange)
                        .tracking(1.1)
                }
                Text("You arrived at \(destination.name).")
                    .font(LFFont.copy(24))
                    .foregroundStyle(LFColor.harborSand)
                    .multilineTextAlignment(.center)
                Text("This voyage stays in your Logbook.")
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.harborSand.opacity(0.55))
                    .padding(.top, 2)
                Spacer()
                Button { onClose() } label: {
                    Text("Close")
                        .font(LFFont.copy(15))
                        .foregroundStyle(LFColor.harborSand)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .overlay(Capsule().strokeBorder(LFColor.harborSand.opacity(0.3), lineWidth: 1))
                }
                .padding(.bottom, 44)
            }
            .padding(.horizontal, 24)
        }
    }
}
