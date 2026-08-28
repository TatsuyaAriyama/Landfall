import SceneKit
import SwiftUI
import UIKit

/// 共有カードの時間帯。色だけでなく、背景の3D航海世界そのものを切り替える。
/// 端末の外観設定には追従させず、SNSへ書き出した絵柄を一定に保つ。
enum DayCardTheme: String, CaseIterable, Identifiable {
    case harbor
    case ink
    case paper

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .harbor: "Sea"
        case .ink: "Night"
        case .paper: "Morning"
        }
    }

    var timeOfDay: AftideHomeTimeOfDay {
        switch self {
        case .harbor: .day
        case .ink: .night
        case .paper: .morning
        }
    }

    /// 配色選択の縮図と、3D描画失敗時の下地に使う。
    var sea: Color {
        switch self {
        case .harbor: Color(hex: 0x56A9AA)
        case .ink: Color(hex: 0x183F3B)
        case .paper: Color(hex: 0x69AAA6)
        }
    }

    var land: Color {
        switch self {
        case .harbor: Color(hex: 0xE7F4EF)
        case .ink: Color(hex: 0x102F2C)
        case .paper: Color(hex: 0xF6EEE1)
        }
    }

    var panel: Color {
        switch self {
        case .harbor: Color(hex: 0x123B40).opacity(0.90)
        case .ink: Color(hex: 0x102F2C).opacity(0.92)
        case .paper: Color(hex: 0xF6EEE1).opacity(0.92)
        }
    }

    var ink: Color {
        switch self {
        case .harbor, .ink: Color(hex: 0xF4F1EC)
        case .paper: Color(hex: 0x173F3C)
        }
    }

    var accent: Color {
        switch self {
        case .harbor: LFColor.sunYellow
        case .ink: LFColor.emberGold
        case .paper: LFColor.returnOrange
        }
    }

    var sceneVeil: Color {
        switch self {
        case .harbor: Color.black.opacity(0.05)
        case .ink: Color.black.opacity(0.11)
        case .paper: Color(hex: 0x173F3C).opacity(0.03)
        }
    }

    var border: Color {
        switch self {
        case .paper: LFColor.inkFixed.opacity(0.12)
        case .harbor, .ink: .clear
        }
    }
}

/// 一日の記録を、実際の航海世界に載せる4:5の共有カード。
/// 背景はホーム／航海中と同じ船・航海士・海・島をSceneKitで描き、
/// 3倍書き出し時に1170×1464pxになる固定寸法で構成する。
struct DayLogCard: View {
    let log: DayLog
    var theme: DayCardTheme = .harbor

    private let cardHeight: CGFloat = 488
    private let inset: CGFloat = 18

    private var visibleEntries: [DayLog.Entry] {
        Array(log.entries.prefix(2))
    }

    private var hiddenEntryCount: Int {
        max(0, log.entries.count - visibleEntries.count)
    }

    var body: some View {
        ZStack {
            voyageBackdrop
            theme.sceneVeil

            VStack(alignment: .leading, spacing: 0) {
                masthead
                voyageSummary
                    .padding(.top, 22)

                Spacer(minLength: 28)

                logPanel
            }
            .padding(inset)
        }
        .frame(width: LFMetrics.cardSize.width, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
        .environment(\.lfFixedType, true)
        .environment(\.colorScheme, .light)
        .environment(\.locale, AppLanguage.current.locale)
    }

    private var voyageBackdrop: some View {
        Group {
            if let image = ShareVoyageBackdropRenderer.image(for: theme) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                theme.sea
            }
        }
        .frame(width: LFMetrics.cardSize.width, height: cardHeight)
        .clipped()
        .accessibilityHidden(true)
    }

    private var masthead: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(verbatim: LF.dayWithWeekday(log.date))
                .font(LFFont.labelFixed(12))
                .tracking(1.6)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(verbatim: "KeelMira")
                .font(LFFont.labelFixed(13))
                .tracking(1.1)
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(theme.panel)
        .clipShape(Capsule(style: .continuous))
    }

    private var voyageSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Today's voyage")
                .font(LFFont.labelFixed(11))
                .tracking(1.5)
                .foregroundStyle(theme.ink.opacity(0.72))

            if log.isRestDay {
                Text("Rested.")
                    .font(LFFont.copyFixed(31))
                    .foregroundStyle(theme.accent)
                Text("A day at harbor is part of the voyage.")
                    .font(LFFont.labelFixed(12))
                    .foregroundStyle(theme.ink.opacity(0.82))
                    .lineLimit(1)
            } else {
                heroTime
                if let gap = log.daysSinceLastVoyage, gap >= 2 {
                    Text("First sail in \(gap) days.")
                        .font(LFFont.labelFixed(12))
                        .foregroundStyle(theme.ink.opacity(0.82))
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .fixedSize(horizontal: true, vertical: true)
    }

    private var heroTime: some View {
        let hours = log.totalMinutes / 60
        let minutes = log.totalMinutes % 60
        let isJa = AppLanguage.current.locale.identifier.hasPrefix("ja")
        let hourUnit = isJa ? "時間" : "h"
        let minuteUnit = isJa ? "分" : "m"

        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            if hours > 0 {
                Text(verbatim: "\(hours)")
                    .font(LFFont.numberFixed(42))
                    .foregroundStyle(theme.accent)
                Text(verbatim: hourUnit)
                    .font(LFFont.labelFixed(14))
                    .foregroundStyle(theme.ink.opacity(0.85))
                    .padding(.trailing, minutes > 0 ? 6 : 0)
            }
            if minutes > 0 || hours == 0 {
                Text(verbatim: "\(minutes)")
                    .font(LFFont.numberFixed(42))
                    .foregroundStyle(theme.accent)
                Text(verbatim: minuteUnit)
                    .font(LFFont.labelFixed(14))
                    .foregroundStyle(theme.ink.opacity(0.85))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }

    private var logPanel: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                if log.isRestDay {
                    Text("A day at harbor is part of the voyage.")
                        .font(LFFont.copyFixed(14))
                        .foregroundStyle(theme.ink.opacity(0.86))
                } else {
                    ForEach(visibleEntries) { entry in
                        entryRow(entry)
                    }

                    if hiddenEntryCount > 0 {
                        Text("and \(hiddenEntryCount) more.")
                            .font(LFFont.labelFixed(11))
                            .foregroundStyle(theme.ink.opacity(0.62))
                            .padding(.top, 3)
                    }
                }

                if let comment = log.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !comment.isEmpty {
                    Text(verbatim: "“\(comment)”")
                        .font(LFFont.copyFixed(13))
                        .foregroundStyle(theme.ink.opacity(0.88))
                        .lineLimit(2)
                        .padding(.top, 10)
                }

                Text("Your day, under sail.")
                    .font(LFFont.labelFixed(10))
                    .tracking(0.8)
                    .foregroundStyle(theme.ink.opacity(0.52))
                    .padding(.top, 13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            promotionQR
        }
        .padding(15)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func entryRow(_ entry: DayLog.Entry) -> some View {
        HStack(spacing: 9) {
            TokenTile(styleToken: entry.styleToken, symbolToken: entry.symbolToken)
                .frame(width: 27, height: 27)

            Text(verbatim: entry.name)
                .font(LFFont.labelFixed(13))
                .foregroundStyle(theme.ink)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(verbatim: LF.duration(minutes: entry.minutes))
                .font(LFFont.numberFixed(12))
                .foregroundStyle(theme.ink.opacity(0.72))
                .lineLimit(1)
        }
        .frame(height: 32)
    }

    @ViewBuilder
    private var promotionQR: some View {
        if let qr = LandfallLink.qrImage(for: LandfallLink.sharePromotionURL) {
            VStack(spacing: 5) {
                Image(uiImage: qr)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 48, height: 48)
                    .padding(6)
                    .background(Color(hex: 0xF6EEE1))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text("Sail with me")
                    .font(LFFont.labelFixed(8))
                    .foregroundStyle(theme.ink.opacity(0.68))
                    .lineLimit(1)
            }
            .frame(width: 64)
            .fixedSize(horizontal: true, vertical: true)
            .layoutPriority(2)
            .accessibilityElement(children: .combine)
        }
    }
}

/// 航海ホームと同じSceneKit世界を共有画像用に決定的な一枚へ焼き付ける。
/// 共有カードの3倍書き出しと同じ実画素で先に描くため、船や海の輪郭がぼやけない。
@MainActor
private enum ShareVoyageBackdropRenderer {
    private static var cachedImages: [String: UIImage] = [:]
    private static let renderSize = CGSize(width: 1170, height: 1464)

    static func image(for theme: DayCardTheme) -> UIImage? {
        let key = "\(theme.rawValue)-\(BoatCustomization.appearanceKey)"
        if let cached = cachedImages[key] { return cached }

        let renderTime: TimeInterval = 3.4
        let scene = VoyageSceneKit.makeVoyagingScene(
            showIsland: true,
            timeOfDay: theme.timeOfDay,
            oceanTime: Float(renderTime),
            nativeMetalRollout: .stillImage
        )

        // アニメータが無い静止画でも、島を航路の先に置き、カモメを原点へ固めない。
        scene.rootNode.childNode(withName: "approachingIsland", recursively: false)?.position =
            SCNVector3(10.4, 0, -8.7)
        scene.rootNode.childNode(withName: "gulls", recursively: false)?.isHidden = true
        scene.rootNode.childNode(withName: "boatBob", recursively: true)?.position.y = 0.04

        guard let camera = scene.rootNode.childNode(withName: "camera", recursively: true) else {
            return nil
        }
        camera.position = SCNVector3(-5.2, 2.6, 8.2)
        // 船体まで情報パネルへ沈まないよう、狙点を水面寄りへ下げて世界を上へ送る。
        camera.look(at: SCNVector3(0.55, 0.78, -0.25))
        camera.camera?.fieldOfView = 40
        camera.camera?.wantsExposureAdaptation = false

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        renderer.autoenablesDefaultLighting = false
        let image = renderer.snapshot(
            atTime: renderTime,
            with: renderSize,
            antialiasingMode: .multisampling4X
        )
        cachedImages[key] = image
        return image
    }
}

/// 項目のトークンだけでタイルを描く(SwiftDataのオブジェクトに依存しない)。
private struct TokenTile: View {
    let styleToken: String
    let symbolToken: String

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let style = TileStyle.from(styleToken)
            ZStack {
                style.background
                TileSymbolView(
                    symbol: TileSymbol.from(symbolToken),
                    fg: style.foreground,
                    bg: style.background
                )
                .frame(width: s * 0.62, height: s * 0.62)
            }
            .frame(width: s, height: s)
            .clipShape(RoundedRectangle(cornerRadius: s * 0.26, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview("学んだ日") {
    DayLogCard(
        log: DayLog(
            date: .now,
            entries: [
                .init(id: "1", name: "開発", styleToken: "midnight", symbolToken: "phoenix", minutes: 95),
                .init(id: "2", name: "読書", styleToken: "coral", symbolToken: "book", minutes: 40),
            ],
            notes: [],
            comment: "久しぶりに読書に没頭できた。",
            totalMinutes: 135,
            sessionCount: 2,
            daysSinceLastVoyage: 6
        ),
        theme: .harbor
    )
}

#Preview("休んだ日") {
    DayLogCard(
        log: DayLog(
            date: .now, entries: [], notes: [], comment: nil,
            totalMinutes: 0, sessionCount: 0, daysSinceLastVoyage: nil
        ),
        theme: .ink
    )
}
