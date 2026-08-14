import Foundation
import SwiftData

/// ステップ目標の1つの目印(順序付き)。達成で doneAt が立つ。
/// SwiftData には Codable 値型の配列として格納し、Firestore の steps 配列(map配列)と
/// そのまま対応する(Web版 destinations.ts の DestinationStep と同一シェイプ)。
struct DestinationStep: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var scheduledAt: Date?
    var doneAt: Date?

    init(
        id: String = UUID().uuidString,
        name: String,
        scheduledAt: Date? = nil,
        doneAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.scheduledAt = scheduledAt
        self.doneAt = doneAt
    }
}

/// 目的地(島)。学習の目標を島として置き、記録するたび船が近づく。到達した日が Landfall(着岸)。
/// Firestore `users/{uid}/destinations/{uuid}` と同期(Web版と同一シェイプ)。
/// 現行UIの目標は2種類: 期日(`targetDate`)/ ステップ(`steps`)。
/// 旧Web版で作られた累計時間・完了目標も、表示と同期で失わない。
@Model
final class Destination {
    /// Firestore の doc ID(= uuid.uuidString)。Web の {uuid} と対応。
    var uuid: UUID
    var name: String
    var createdAt: Date
    /// 端末間の競合解決(Last-Write-Wins)。既定値で軽量マイグレーション可。
    var updatedAt: Date = Date.distantPast
    /// 期日目標の締切。経過時間で船が近づく。
    var targetDate: Date?
    /// trueならtargetDateの時刻まで締切に含める。falseならその日の23:59:59.999。
    var targetHasTime: Bool = false
    /// 旧Web版との読み書き互換。設定されていれば対象項目の記録だけを数える。
    var itemUUID: String?
    /// 旧Web版の累計時間目標。
    var targetMinutes: Int?
    /// 旧Web版の手動完了目標。
    var manual: Bool = false
    var manualDone: Bool = false
    /// 着岸した日時。設定後は「到達した島」。
    var achievedAt: Date?
    /// ステップ目標の目印(順序付き)。非空ならステップ目標として扱う。
    var steps: [DestinationStep] = []

    init(
        name: String,
        createdAt: Date = Date(),
        targetDate: Date? = nil,
        targetHasTime: Bool = false,
        itemUUID: String? = nil,
        targetMinutes: Int? = nil,
        manual: Bool = false,
        manualDone: Bool = false,
        steps: [DestinationStep] = []
    ) {
        self.uuid = UUID()
        self.name = name
        self.createdAt = createdAt
        self.targetDate = targetDate
        self.targetHasTime = targetHasTime
        self.itemUUID = itemUUID
        self.targetMinutes = targetMinutes
        self.manual = manual
        self.manualDone = manualDone
        self.steps = Array(steps.prefix(Self.maxSteps))
        self.updatedAt = Date()
    }

    /// ステップの上限。分解しすぎて航路が埋まらない程度に抑える(Web と同じ)。
    static let maxSteps = 3

    /// Web版 `destinationDeadline` と同じ締切解釈。
    func deadline(calendar: Calendar = .current) -> Date? {
        guard let targetDate else { return nil }
        if targetHasTime { return targetDate }
        let start = calendar.startOfDay(for: targetDate)
        return calendar.date(byAdding: DateComponents(day: 1, nanosecond: -1), to: start)
    }
}
