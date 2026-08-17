import SwiftUI

/// 日常操作を、ゲーム内の航海図として確認できる実用ガイド。
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chapter: HelpChapter = .items

    var body: some View {
        ZStack {
            HelpOceanChartBackground()

            VStack(spacing: 0) {
                gameHeader
                chapterPicker

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        chapterHeading
                        chapterContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 34)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .id(chapter)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            #if DEBUG
            if let rawValue = ProcessInfo.processInfo.environment["LANDFALL_HELP_CHAPTER"],
               let requested = HelpChapter(rawValue: rawValue) {
                chapter = requested
            }
            #endif
        }
    }

    private var gameHeader: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
                Haptics.tap(.light)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                    Text("Back")
                        .font(LFFont.label(13))
                }
                .foregroundStyle(LFColor.harborSand)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(.white.opacity(0.07), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(LFPressableButtonStyle())

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text("CAPTAIN'S GUIDE")
                    .font(LFFont.label(9))
                    .tracking(2.2)
                    .foregroundStyle(LFColor.returnOrange)
                Text("Help")
                    .font(LFFont.copy(21))
                    .foregroundStyle(LFColor.harborSand)
            }

            Spacer(minLength: 8)

            ZStack {
                Circle().stroke(LFColor.harborSand.opacity(0.28), lineWidth: 1)
                Circle()
                    .stroke(
                        LFColor.returnOrange.opacity(0.48),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                    )
                    .padding(5)
                Image(systemName: "compass.drawing")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LFColor.harborSand)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: 0x0D2A24).opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LFColor.harborSand.opacity(0.14))
                .frame(height: 1)
        }
    }

    private var chapterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HelpChapter.allCases) { candidate in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            chapter = candidate
                        }
                        Haptics.tap(.light)
                    } label: {
                        HStack(spacing: 7) {
                            candidate.icon
                                .frame(width: 22, height: 22)
                            Text(candidate.title)
                                .font(LFFont.label(11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(
                            chapter == candidate
                                ? Color(hex: 0x102F2C)
                                : LFColor.harborSand.opacity(0.72)
                        )
                        .padding(.horizontal, 13)
                        .frame(height: 42)
                        .background(
                            chapter == candidate
                                ? LFColor.harborSand
                                : Color.white.opacity(0.055),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    chapter == candidate
                                        ? LFColor.returnOrange.opacity(0.42)
                                        : LFColor.harborSand.opacity(0.14),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityAddTraits(chapter == candidate ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(hex: 0x123830).opacity(0.94))
    }

    private var chapterHeading: some View {
        HStack(alignment: .center, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LFColor.returnOrange.opacity(0.16))
                chapter.largeIcon
                    .frame(width: 38, height: 38)
            }
            .frame(width: 58, height: 58)
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(LFColor.returnOrange.opacity(0.36), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.eyebrow)
                    .font(LFFont.label(9))
                    .tracking(1.8)
                    .foregroundStyle(LFColor.returnOrange)
                Text(chapter.heading)
                    .font(LFFont.copy(22))
                    .foregroundStyle(LFColor.harborSand)
                Text(chapter.summary)
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.harborSand.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var chapterContent: some View {
        switch chapter {
        case .items:
            ItemTapChart()
            GameGuideCard(title: "Work items", route: "01 · DECK") {
                GameGuideStep(
                    icon: .add,
                    title: "Add an item",
                    detail: "Tap + at the end of the work item list."
                )
                GameGuideStep(
                    icon: .itemName,
                    title: "Edit an item",
                    detail: "Tap the item name below its picture. You can change its name, color, and symbol."
                )
                GameGuideStep(
                    icon: .reorder,
                    title: "Reorder items",
                    detail: "Touch and hold a tile, then drag it to a new position."
                )
                GameGuideStep(
                    icon: .delete,
                    title: "Delete an item",
                    detail: "Open Edit item, then tap Delete item at the bottom."
                )
            }

        case .timer:
            GameGuideCard(title: "Timer", route: "02 · VOYAGE CLOCK") {
                GameGuideStep(
                    icon: .workTile,
                    title: "Start timing",
                    detail: "Tap a work item's picture."
                )
                GameGuideStep(
                    icon: .minimize,
                    title: "Keep timing on Home",
                    detail: "Tap × on the voyage clock. The timer continues in the panel at the bottom of Home."
                )
                GameGuideStep(
                    icon: .pause,
                    title: "Pause the timer",
                    detail: "Tap Pause in the timer panel. Tap Resume when you return."
                )
                GameGuideStep(
                    icon: .finish,
                    title: "Finish and save",
                    detail: "Tap End and record to stop with one tap and save the elapsed time."
                )
            }

        case .records:
            GameGuideCard(title: "Destination and records", route: "03 · CHART") {
                GameGuideStep(
                    icon: .destination,
                    title: "Set a destination",
                    detail: "Tap the destination below your player card at the top left of Home."
                )
                GameGuideStep(
                    icon: .date,
                    title: "Open Trace",
                    detail: "Tap the date in the top-left corner of Home."
                )
                GameGuideStep(
                    icon: .logbook,
                    title: "Open Logbook",
                    detail: "Open the top-right menu and choose Logbook."
                )
                GameGuideStep(
                    icon: .menu,
                    title: "Open another deck",
                    detail: "Use the top-right menu to open My Island, Harbor, Logbook, Style, Help, or Settings."
                )
            }

        case .island:
            GameGuideCard(title: "My Island", route: "04 · ASHORE") {
                GameGuideStep(
                    icon: .island,
                    title: "Visit your island",
                    detail: "Open the top-right menu and choose My Island."
                )
                GameGuideStep(
                    icon: .islandEdit,
                    title: "Build and explore",
                    detail: "Use Edit to place items. Switch to Explore to walk around."
                )
                GameGuideStep(
                    icon: .campfire,
                    title: "Open Logbook at the campfire",
                    detail: "Walk close to the campfire and tap it."
                )
                GameGuideStep(
                    icon: .tent,
                    title: "Enter the tent",
                    detail: "Walk close to the tent and tap it to go inside."
                )
            }
        }
    }
}

private enum HelpChapter: String, CaseIterable, Identifiable {
    case items
    case timer
    case records
    case island

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .items: "Items"
        case .timer: "Timer"
        case .records: "Chart"
        case .island: "Island"
        }
    }

    var eyebrow: LocalizedStringKey {
        switch self {
        case .items: "DECK 01"
        case .timer: "DECK 02"
        case .records: "DECK 03"
        case .island: "DECK 04"
        }
    }

    var heading: LocalizedStringKey {
        switch self {
        case .items: "Choose your work"
        case .timer: "Measure your voyage"
        case .records: "Set a course and look back"
        case .island: "Build a place to return to"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .items: "The picture and name have different actions."
        case .timer: "Start, pause, minimize, or finish from clear controls."
        case .records: "Your destination and records are always close to Home."
        case .island: "Place landmarks, explore, and use the buildings you find."
        }
    }

    @MainActor @ViewBuilder
    var icon: some View {
        switch self {
        case .items:
            TabSymbolIcon.image(.compass).resizable().scaledToFit()
        case .timer:
            Image(systemName: "timer").resizable().scaledToFit().padding(2)
        case .records:
            TabSymbolIcon.image(.book).resizable().scaledToFit()
        case .island:
            TabSymbolIcon.image(.island).resizable().scaledToFit()
        }
    }

    @MainActor @ViewBuilder
    var largeIcon: some View {
        icon
            .foregroundStyle(LFColor.harborSand)
    }
}

/// 「画像」と「項目名」の押し分けを、実際のタイル図案で示す航海図。
private struct ItemTapChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(LFColor.returnOrange)
                Text("Where to tap a work item")
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.harborSand)
                Spacer()
                Text("QUICK MAP")
                    .font(LFFont.label(8))
                    .tracking(1.4)
                    .foregroundStyle(LFColor.harborSand.opacity(0.40))
            }

            HStack(alignment: .top, spacing: 10) {
                tapTarget(
                    icon: .workTile,
                    target: "Picture",
                    action: "Start timing"
                )
                tapTarget(
                    icon: .itemName,
                    target: "Item name",
                    action: "Edit item"
                )
            }
        }
        .padding(16)
        .background(Color(hex: 0x0D2A24).opacity(0.90), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(LFColor.returnOrange.opacity(0.34), lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 40))
                .foregroundStyle(LFColor.harborSand.opacity(0.035))
                .padding(10)
        }
    }

    private func tapTarget(
        icon: GameControlIcon,
        target: LocalizedStringKey,
        action: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            icon.view
                .frame(width: 54, height: 54)
            Text(target)
                .font(LFFont.label(10))
                .foregroundStyle(LFColor.harborSand.opacity(0.50))
            HStack(spacing: 5) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                Text(action)
                    .font(LFFont.copy(14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(LFColor.harborSand)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

private struct GameGuideCard<Content: View>: View {
    let title: LocalizedStringKey
    let route: String
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey,
        route: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.route = route
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: route)
                        .font(LFFont.label(8))
                        .tracking(1.7)
                        .foregroundStyle(LFColor.returnOrange)
                    Text(title)
                        .font(LFFont.copy(18))
                        .foregroundStyle(LFColor.harborSand)
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index == 0 ? LFColor.returnOrange : LFColor.harborSand.opacity(0.18))
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                content
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x173F3B).opacity(0.95), Color(hex: 0x102F2C).opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LFColor.harborSand.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 18, y: 10)
    }
}

private struct GameGuideStep: View {
    let icon: GameControlIcon
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            icon.view
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.harborSand)
                Text(detail)
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.harborSand.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LFColor.harborSand.opacity(0.08))
                .frame(height: 1)
                .padding(.leading, 61)
        }
    }
}

/// 本編の記号・色・ボタン形状を縮小して、そのまま説明へ使う。
private enum GameControlIcon {
    case workTile
    case itemName
    case add
    case reorder
    case delete
    case minimize
    case pause
    case finish
    case destination
    case date
    case logbook
    case menu
    case island
    case islandEdit
    case campfire
    case tent

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .workTile:
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(TileStyle.coral.background)
                TileSymbolView(
                    symbol: .book,
                    fg: TileStyle.coral.foreground,
                    bg: TileStyle.coral.background
                )
                .padding(9)
            }
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14), lineWidth: 1))

        case .itemName:
            VStack(spacing: 1) {
                Text("Reading")
                    .font(LFFont.label(9))
                    .lineLimit(1)
                Text(verbatim: LF.duration(minutes: 105))
                    .font(LFFont.label(8))
                    .foregroundStyle(LFColor.returnOrange)
            }
            .foregroundStyle(LFColor.harborSand)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0x173F3B), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(LFColor.harborSand.opacity(0.24), lineWidth: 1))

        case .add:
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(LFColor.harborSand.opacity(0.42), style: StrokeStyle(lineWidth: 1.3, dash: [5, 4]))
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(LFColor.harborSand)
            }

        case .reorder:
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(TileStyle.midnight.background)
                TileSymbolView(symbol: .compass, fg: TileStyle.midnight.foreground, bg: TileStyle.midnight.background)
                    .padding(10)
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LFColor.paper)
                    .padding(5)
                    .background(LFColor.returnOrange, in: Circle())
                    .offset(x: 17, y: -17)
            }

        case .delete:
            controlButton(systemName: "trash.fill", foreground: LFColor.paper, background: LFColor.deepRust)

        case .minimize:
            controlButton(systemName: "xmark", foreground: LFColor.harborSand, background: .white.opacity(0.09))

        case .pause:
            controlButton(systemName: "pause.fill", foreground: LFColor.harborSand, background: LFColor.harborSand.opacity(0.12))

        case .finish:
            controlButton(systemName: "stop.fill", foreground: LFColor.paper, background: LFColor.returnOrange)

        case .destination:
            tileSymbol(.island, style: .seaGreen)

        case .date:
            VStack(spacing: 0) {
                Text("SAT")
                    .font(LFFont.label(7))
                    .foregroundStyle(LFColor.returnOrange)
                Text("8/9")
                    .font(LFFont.number(12))
                    .foregroundStyle(LFColor.harborSand)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(LFColor.harborSand.opacity(0.18), lineWidth: 1))

        case .logbook:
            tileSymbol(.book, style: .coral)

        case .menu:
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.07))
                HStack(spacing: 3) {
                    Text("Home")
                        .font(LFFont.label(9))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(LFColor.harborSand)
            }

        case .island:
            tileSymbol(.island, style: .seaGreen)

        case .islandEdit:
            controlButton(systemName: "hammer.fill", foreground: LFColor.harborSand, background: .white.opacity(0.09))

        case .campfire:
            controlButton(systemName: "flame.fill", foreground: LFColor.sunYellow, background: LFColor.deepRust.opacity(0.52))

        case .tent:
            controlButton(systemName: "tent.fill", foreground: LFColor.harborSand, background: .white.opacity(0.09))
        }
    }

    @MainActor
    private func controlButton(
        systemName: String,
        foreground: Color,
        background: Color
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.11), lineWidth: 1))
    }

    @MainActor
    private func tileSymbol(_ symbol: TileSymbol, style: TileStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(style.background)
            TileSymbolView(symbol: symbol, fg: style.foreground, bg: style.background)
                .padding(9)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

/// 星・海図の航路・波を固定座標で描き、ヘルプも本編の海上に置く。
private struct HelpOceanChartBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x102F2C), Color(hex: 0x173F3B), Color(hex: 0x0D2A24)],
                startPoint: .top,
                endPoint: .bottom
            )

            Canvas { context, size in
                for index in 0..<36 {
                    let x = CGFloat((index * 47) % 101) / 100 * size.width
                    let y = CGFloat((index * 71) % 79) / 100 * size.height * 0.72
                    let radius: CGFloat = index.isMultiple(of: 5) ? 1.4 : 0.8
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                        with: .color(LFColor.harborSand.opacity(index.isMultiple(of: 4) ? 0.28 : 0.14))
                    )
                }

                var route = Path()
                route.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.26))
                route.addCurve(
                    to: CGPoint(x: size.width * 0.92, y: size.height * 0.60),
                    control1: CGPoint(x: size.width * 0.42, y: size.height * 0.15),
                    control2: CGPoint(x: size.width * 0.58, y: size.height * 0.72)
                )
                context.stroke(
                    route,
                    with: .color(LFColor.harborSand.opacity(0.08)),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 8])
                )

                for row in 0..<8 {
                    var wave = Path()
                    let y = size.height * 0.68 + CGFloat(row) * 26
                    wave.move(to: CGPoint(x: 0, y: y))
                    for column in 0...8 {
                        let x = CGFloat(column) / 8 * size.width
                        let offset = column.isMultiple(of: 2) ? CGFloat(6) : CGFloat(-6)
                        wave.addLine(to: CGPoint(x: x, y: y + offset))
                    }
                    context.stroke(wave, with: .color(Color(hex: 0x69AAA6).opacity(0.07)), lineWidth: 1)
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}
