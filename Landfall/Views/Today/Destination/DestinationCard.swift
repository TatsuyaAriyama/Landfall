import SwiftUI

/// ホームの目的地カード。夜の海の3D(船が進む/ブイが点灯)+ 島名・進捗のオーバーレイ。
/// 目的地が未設定でも、同じ夜の海が見えている(タップで設定へ)。Web版 DestinationCard 相当。
struct DestinationCard: View {
    let destination: Destination?
    let sessions: [StudySession]
    var onTap: () -> Void
    var onLand: ((Destination) -> Void)?
    var onMarkDone: ((Destination) -> Void)?

    init(
        destination: Destination?,
        sessions: [StudySession],
        onLand: ((Destination) -> Void)? = nil,
        onMarkDone: ((Destination) -> Void)? = nil,
        onTap: @escaping () -> Void
    ) {
        self.destination = destination
        self.sessions = sessions
        self.onTap = onTap
        self.onLand = onLand
        self.onMarkDone = onMarkDone
    }

    private var progress: DestinationProgress? {
        destination?.progress(sessions: sessions)
    }

    var body: some View {
        // 空状態はやや進んだ位置に船を置いて「もう海がある」感を出す(Web EmptySeaCard と同じ)。
        let ratio = progress?.ratio ?? 0.32
        let stepFlags = destination?.steps.map { VoyageStep(doneAt: $0.doneAt) } ?? []

        ZStack(alignment: .bottom) {
            Button(action: onTap) {
                ZStack(alignment: .top) {
                    VoyageSceneView(ratio: ratio, steps: stepFlags)
                    overlay
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
            }
            .buttonStyle(LFPressableButtonStyle())

            if let destination,
               (!destination.manual || destination.manualDone),
               let onLand {
                Button {
                    onLand(destination)
                } label: {
                    Text("Go ashore")
                        .font(LFFont.copy(14))
                        .foregroundStyle(LFColor.inkFixed)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 38)
                        .background(LFColor.harborSand, in: Capsule())
                }
                .buttonStyle(LFPressableButtonStyle())
                .padding(.bottom, 14)
            }

            if let destination, destination.manual, !destination.manualDone, let onMarkDone {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            onMarkDone(destination)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(LFColor.harborSand)
                                .frame(width: 30, height: 30)
                                .background(
                                    Color(VoyageSceneKit.seaDeep).opacity(0.72),
                                    in: Circle()
                                )
                                .overlay(
                                    Circle()
                                        .stroke(LFColor.harborSand.opacity(0.36), lineWidth: 1)
                                )
                        }
                        .buttonStyle(LFPressableButtonStyle())
                        .accessibilityLabel(Text("Mark complete"))
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var overlay: some View {
        if let destination, let progress {
            VStack(alignment: .leading, spacing: 4) {
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
                // 直近で辿り着いた小島と、その日付(小さなオレンジ文字)。
                if let latest = destination.latestDoneStep {
                    Text(verbatim: "\(latest.name) · \(LF.dayMonth(latest.doneAt ?? Date()))")
                        .font(LFFont.label(11))
                        .foregroundStyle(LFColor.returnOrange)
                        .lineLimit(1)
                }
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
        if progress.reached {
            Text("Ready to go ashore")
        } else if progress.stepsTotal != nil {
            if let next = destination.nextStepName {
                Text("Next: \(next)")
            } else {
                Text(verbatim: "\(progress.stepsDone ?? 0) / \(progress.stepsTotal ?? 0)")
            }
        } else if let minutes = progress.remainingMinutes {
            Text(remainingMinutesLabel(minutes))
        } else if let seconds = progress.remainingSeconds {
            Text(deadlineRemainingLabel(seconds))
        } else if let days = progress.remainingDays {
            Text("\(days) days left")
        }
    }

    private func remainingMinutesLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return LF.format("%lld minutes left", Int64(minutes))
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return LF.format("%lld hours left", Int64(hours))
        }
        return LF.format(
            "%lld hours %lld minutes left",
            Int64(hours),
            Int64(remainder)
        )
    }

    private func deadlineRemainingLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(ceil(seconds / 60)))
        if minutes < 24 * 60 {
            return remainingMinutesLabel(minutes)
        }
        let days = Int(ceil(seconds / 86_400))
        return LF.format("%lld days left", Int64(days))
    }
}
