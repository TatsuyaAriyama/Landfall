import SwiftUI
import SwiftData

/// 出航中(タイマー計測中)に画面へ浮かぶ小さなチップ。
/// 作業名と経過時間を表示し、指で自由に動かせる。タップで記録シートを開き、着岸できる。
/// どのタブでも見えるよう ContentView 直下に重ねる。
struct FloatingTimerChip: View {
    @AppStorage(StudyTimer.startKey) private var timerStart: Double = 0
    @AppStorage(StudyTimer.itemKey) private var timerItemID: String = ""
    @Query private var items: [StudyItem]

    /// チップの停泊位置。動かした場所を覚えておく(-1は未設定=既定位置)。
    @AppStorage("landfall.timer.chip.x") private var storedX: Double = -1
    @AppStorage("landfall.timer.chip.y") private var storedY: Double = -1
    @GestureState private var dragOffset: CGSize = .zero
    @State private var landing: StudyItem?

    private var sailingItem: StudyItem? {
        guard timerStart > 0 else { return nil }
        return items.first { $0.uuid.uuidString == timerItemID }
    }

    var body: some View {
        GeometryReader { geo in
            if let item = sailingItem {
                chip(for: item)
                    .position(currentPosition(in: geo.size))
                    .gesture(drag(in: geo.size))
                    .onTapGesture { landing = item }
            }
        }
        .sheet(item: $landing) { item in
            RecordSessionSheet(item: item, onSaved: { _ in }, onEdit: { _ in })
        }
        .onAppear { debugStartTimerIfRequested() }
        .onChange(of: items.count) { _, _ in debugStartTimerIfRequested() }
    }

    /// 動作確認用: LANDFALL_TIMER=1 で最初の項目のタイマーを起動した状態にする。
    /// LANDFALL_SEED は毎起動で項目を作り直す(UUIDが変わる)ため、
    /// 保存済みのタイマーが現存の項目を指していなければ紐付け直す。
    private func debugStartTimerIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["LANDFALL_TIMER"] == "1",
              let first = items.first else { return }
        let valid = items.contains { $0.uuid.uuidString == timerItemID }
        if timerStart == 0 || !valid {
            timerStart = Date().timeIntervalSince1970 - 754   // 12分34秒経過
            timerItemID = first.uuid.uuidString
        }
        #endif
    }

    // MARK: - 見た目

    private func chip(for item: StudyItem) -> some View {
        HStack(spacing: 12) {
            BoatShape()
                .fill(LFColor.harborSand)
                .frame(width: 15, height: 27)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.harborSand.opacity(0.85))
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedText(at: context.date))
                        .font(LFFont.number(19))
                        .monospacedDigit()
                        .foregroundStyle(LFColor.harborSand)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(LFColor.harborTeal)
        .clipShape(Capsule(style: .continuous))
        .frame(maxWidth: 230)
    }

    private func elapsedText(at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince1970 - timerStart))
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    // MARK: - 位置とドラッグ

    /// 既定は右下(タブバーの上)。保存位置があればそこへ、ドラッグ中はその分ずらす。
    private func currentPosition(in size: CGSize) -> CGPoint {
        let base: CGPoint = storedX >= 0
            ? CGPoint(x: storedX, y: storedY)
            : CGPoint(x: size.width - 128, y: size.height - 130)
        return clamp(
            CGPoint(x: base.x + dragOffset.width, y: base.y + dragOffset.height),
            in: size
        )
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let base: CGPoint = storedX >= 0
                    ? CGPoint(x: storedX, y: storedY)
                    : CGPoint(x: size.width - 128, y: size.height - 130)
                let landed = clamp(
                    CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height),
                    in: size
                )
                storedX = landed.x
                storedY = landed.y
            }
    }

    /// 画面の外・状態バー・タブバーに埋もれないよう停泊位置を制限する。
    private func clamp(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 110), size.width - 110),
            y: min(max(point.y, 70), size.height - 120)
        )
    }
}
