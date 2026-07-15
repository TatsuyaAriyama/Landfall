import SwiftUI

/// 当月の学習記録をスカイライン(ステップ)状の軌跡として描く独立View。
/// Wrappedカードのほか「軌跡」画面でも再利用するため、色はすべて注入する。
/// - 学習日 = 持ち上がった台地。連続するほど一段ずつ高くなる(勢いの表現)
/// - 空白日 = ベースライン
/// - significantGaps = 下部の角丸バー + 「◯日の空白」ラベル
/// - resumeDays = 立ち上がりの角のマーカー + 「帰還」ラベル
struct MonthWaveform: View {
    let month: WrappedMonth
    let lineColor: Color
    let gapBarColor: Color
    let resumeMarkerColor: Color
    var gapLabelColor: Color? = nil
    /// 下部に日付軸(週ごとの日番号)を描くか。軌跡画面ではtrue、共有カードでは既定のfalse。
    var showDateAxis: Bool = false

    // MARK: レイアウト定数

    private let lineWidth: CGFloat = 3
    private let resumeBandHeight: CGFloat = 34   // 上部「帰還」ラベル帯
    private let gapBandHeight: CGFloat = 46      // 下部 空白バー+ラベル帯
    private var axisHeight: CGFloat { showDateAxis ? 22 : 0 }  // 日付軸のぶん
    private let markerDiameter: CGFloat = 9
    private let gapBarHeight: CGFloat = 7
    /// 台地の高さ: 連続1日目の高さと、連続するごとの上がり幅(帯に対する割合)
    private let baseRise: CGFloat = 0.60
    private let stepRise: CGFloat = 0.09
    /// 「帰還」ラベル同士がこれ未満に近づくときは間引く(点は残す)
    private let minResumeLabelSpacing: CGFloat = 34
    /// バーがこれより狭いときはラベルを「◯日」に省略する
    private let shortGapLabelThreshold: CGFloat = 45

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let dayWidth = width / CGFloat(month.daysInMonth)
            let topY = resumeBandHeight
            let baselineY = geo.size.height - gapBandHeight - axisHeight
            let labeledResumes = labeledResumeDays(dayWidth: dayWidth)

            ZStack(alignment: .topLeading) {
                // 軌跡本体
                tracePath(width: width, dayWidth: dayWidth, topY: topY, baselineY: baselineY)
                    .stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                // 空白区間: 角丸バー + ラベル
                ForEach(month.significantGaps) { gap in
                    let startX = CGFloat(gap.startDay - 1) * dayWidth + 2
                    let endX = CGFloat(gap.endDay) * dayWidth - 2
                    let midX = (startX + endX) / 2

                    Capsule(style: .continuous)
                        .fill(gapBarColor)
                        .frame(width: max(endX - startX, gapBarHeight), height: gapBarHeight)
                        .position(x: midX, y: baselineY + 14 + gapBarHeight / 2)

                    Text(gapLabel(for: gap, barWidth: endX - startX))
                        .font(LFFont.label(11))
                        .foregroundStyle(gapLabelColor ?? lineColor.opacity(0.55))
                        .position(x: midX, y: baselineY + 14 + gapBarHeight + 14)
                }

                // 帰還: 立ち上がりの角のマーカー + ラベル(密集時はラベルのみ間引く)
                ForEach(month.resumeDays, id: \.self) { day in
                    let x = CGFloat(day - 1) * dayWidth
                    let y = levelY(of: day, topY: topY, baselineY: baselineY)

                    Circle()
                        .fill(resumeMarkerColor)
                        .frame(width: markerDiameter, height: markerDiameter)
                        .position(x: x, y: y)

                    if labeledResumes.contains(day) {
                        Text("Return")
                            .font(LFFont.copy(12))
                            .foregroundStyle(resumeMarkerColor)
                            .position(x: min(max(x, 14), width - 14), y: y - 20)
                    }
                }

                // 日付軸: 週ごとの日番号 + 短い目盛り
                if showDateAxis {
                    ForEach(axisDays, id: \.self) { day in
                        let x = (CGFloat(day) - 0.5) * dayWidth
                        Rectangle()
                            .fill(lineColor.opacity(0.2))
                            .frame(width: 1, height: 5)
                            .position(x: x, y: baselineY + gapBandHeight + 2)
                        Text("\(day)")
                            .font(LFFont.label(11))
                            .monospacedDigit()
                            .foregroundStyle(lineColor.opacity(0.4))
                            .position(x: min(max(x, 8), width - 8), y: baselineY + gapBandHeight + 13)
                    }
                }
            }
        }
    }

    /// 日付軸に出す日(1日始まりで7日ごと、最終日も添える)。
    private var axisDays: [Int] {
        var days = Array(stride(from: 1, through: month.daysInMonth, by: 7))
        if let last = days.last, month.daysInMonth - last >= 3 {
            days.append(month.daysInMonth)
        }
        return days
    }

    // MARK: 導出

    /// 各学習日が連続ブロックの何日目か(0始まり)。
    private var blockIndex: [Int: Int] {
        var result: [Int: Int] = [:]
        for day in month.studiedDays.sorted() {
            result[day] = month.studiedDays.contains(day - 1) ? (result[day - 1] ?? 0) + 1 : 0
        }
        return result
    }

    /// その日の台地の高さ(y座標)。空白日はベースライン。
    private func levelY(of day: Int, topY: CGFloat, baselineY: CGFloat) -> CGFloat {
        guard let index = blockIndex[day] else { return baselineY }
        let fraction = min(baseRise + stepRise * CGFloat(index), 1.0)
        return baselineY - fraction * (baselineY - topY)
    }

    /// 月全体をひと筆のステップ波形として描く。
    private func tracePath(width: CGFloat, dayWidth: CGFloat, topY: CGFloat, baselineY: CGFloat) -> Path {
        var path = Path()
        var currentY = baselineY
        path.move(to: CGPoint(x: 0, y: currentY))
        for day in 1...month.daysInMonth {
            let y = levelY(of: day, topY: topY, baselineY: baselineY)
            let x = CGFloat(day - 1) * dayWidth
            if y != currentY {
                path.addLine(to: CGPoint(x: x, y: currentY))
                path.addLine(to: CGPoint(x: x, y: y))
                currentY = y
            }
            path.addLine(to: CGPoint(x: CGFloat(day) * dayWidth, y: y))
        }
        return path
    }

    /// 狭いバーでは「◯日」に省略し、隣のラベルとの重なりを避ける。ロケール準拠で解決。
    private func gapLabel(for gap: GapSpan, barWidth: CGFloat) -> String {
        barWidth < shortGapLabelThreshold
            ? String(localized: "\(gap.length)d")
            : String(localized: "\(gap.length)-day gap")
    }

    /// 「帰還」ラベルを付ける再開日。近すぎるものは先勝ちで間引く。
    private func labeledResumeDays(dayWidth: CGFloat) -> Set<Int> {
        var result: Set<Int> = []
        var lastLabeledX: CGFloat = -.greatestFiniteMagnitude
        for day in month.resumeDays.sorted() {
            let x = CGFloat(day - 1) * dayWidth
            if x - lastLabeledX >= minResumeLabelSpacing {
                result.insert(day)
                lastLabeledX = x
            }
        }
        return result
    }
}
