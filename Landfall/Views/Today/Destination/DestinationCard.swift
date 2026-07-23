import SwiftUI

/// ホームの目的地カード。夜の海の3D(船が進む/ブイが点灯)+ 島名・進捗のオーバーレイ。
/// 目的地が未設定でも、同じ夜の海が見えている(タップで設定へ)。Web版 DestinationCard 相当。
struct DestinationCard: View {
    let destination: Destination?
    let sessions: [StudySession]
    var onTap: () -> Void

    private var progress: DestinationProgress? {
        destination?.progress(sessions: sessions)
    }

    var body: some View {
        // 空状態はやや進んだ位置に船を置いて「もう海がある」感を出す(Web EmptySeaCard と同じ)。
        let ratio = progress?.ratio ?? 0.32
        let stepFlags = destination?.steps.map { $0.doneAt != nil } ?? []

        Button(action: onTap) {
            ZStack(alignment: .top) {
                VoyageSceneView(ratio: ratio, steps: stepFlags)
                overlay
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        }
        .buttonStyle(LFPressableButtonStyle())
    }

    @ViewBuilder
    private var overlay: some View {
        if let destination, let progress {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: destination.name)
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.harborSand)
                    .lineLimit(1)
                Spacer(minLength: 12)
                progressLabel(for: destination, progress: progress)
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.harborSand.opacity(0.7))
                    .lineLimit(1)
            }
        } else {
            HStack {
                Text("Set a destination.")
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.harborSand)
                Spacer()
            }
        }
    }

    /// 進捗の一言。ステップ目標=「次: 〈ステップ〉」または「n / m」、期日=「あと◯日」。
    @ViewBuilder
    private func progressLabel(for destination: Destination, progress: DestinationProgress) -> some View {
        if progress.stepsTotal != nil {
            if let next = destination.nextStepName {
                Text("Next: \(next)")
            } else {
                Text(verbatim: "\(progress.stepsDone ?? 0) / \(progress.stepsTotal ?? 0)")
            }
        } else if let days = progress.remainingDays {
            Text("\(days) days left")
        }
    }
}
