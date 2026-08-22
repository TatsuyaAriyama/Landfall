import Foundation

/// `PlayerLevel.swift` をアプリやSwiftDataから切り離して検証する最小モデル。
///
///   swiftc -parse-as-library -O Landfall/Models/PlayerLevel.swift \
///          Tools/RenderHarness/PlayerLevelProbe.swift \
///          -o /tmp/playerlevelprobe && /tmp/playerlevelprobe
final class StudySession {
    let minutes: Int
    let extraSeconds: Int

    init(minutes: Int, extraSeconds: Int = 0) {
        self.minutes = minutes
        self.extraSeconds = extraSeconds
    }
}

@main
enum PlayerLevelProbe {
    static func main() {
        var failures: [String] = []

        func expect(_ condition: Bool, _ message: String) {
            print("\(condition ? "ok  " : "FAIL") \(message)")
            if !condition { failures.append(message) }
        }

        let levelOne = PlayerLevelProgress(totalMinutes: -1)
        expect(levelOne.level == 1 && levelOne.totalMinutes == 0, "負数はレベルへ入らない")

        let boundary = PlayerLevelProgress(totalMinutes: PlayerLevelProgress.minutesPerLevel)
        expect(boundary.level == 2, "600分でレベル2になる")
        expect(boundary.minutesIntoLevel == 0, "レベル境界の進捗は0分から始まる")

        let defended = PlayerLevelProgress(sessions: [
            StudySession(minutes: 30),
            StudySession(minutes: -1),
            StudySession(minutes: WorkRecordPolicy.maximumSessionMinutes + 1),
            StudySession(minutes: 0, extraSeconds: 60),
        ])
        expect(defended.totalMinutes == 30, "異常な同期記録を集計から除外する")

        let saturated = PlayerLevelProgress(totalMinutes: Int.max)
        expect(saturated.level == WorkRecordPolicy.maximumLevel, "巨大な合計は最大レベルで飽和する")
        expect(saturated.minutesToNextLevel == 0, "最大レベルでは次レベルを表示しない")
        expect(saturated.fractionToNextLevel == 1, "最大レベルの進捗表示は完了状態になる")

        print(failures.isEmpty ? "\nすべて通過" : "\n失敗 \(failures.count) 件")
        exit(failures.isEmpty ? 0 : 1)
    }
}
