import SwiftUI

/// 装い。船は帆色だけを選び、航海士は仕草を切り替えて眺める。
struct DressView: View {
    /// 選ぶたびに +1 して、3Dの色と選択枠を更新する。
    @State private var version = 0
    @State private var mode: Mode = Self.initialMode
    /// 航海士のポーズ(待機/歩く/掲げる/手を振る)。選んだ姿は保存され、
    /// 目的地の船の上でも同じ仕草で立つ。
    @State private var navPose: PhoenixPose = {
        #if DEBUG
        if let p = ProcessInfo.processInfo.environment["LANDFALL_NAV_POSE"],
           let pose = PhoenixPose(rawValue: p) { return pose }
        #endif
        return PhoenixPose.selected
    }()

    enum Mode { case boat, navigator }

    private static var initialMode: Mode {
        #if DEBUG
        // 色選択を検証するためのデモ選択。
        if ProcessInfo.processInfo.environment["LANDFALL_DEMO_BOAT"] != nil {
            BoatCustomization.selectSail("coral")
        }
        if ProcessInfo.processInfo.environment["LANDFALL_DRESS_NAV"] != nil { return .navigator }
        #endif
        return .boat
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LFColor.paper.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(mode == .boat ? "Your boat" : "Your navigator")
                            .font(LFFont.copy(26))
                            .foregroundStyle(LFColor.ink)
                            .padding(.top, 32)
                            .padding(.horizontal, 24)

                        HStack(spacing: 10) {
                            modeChip("Boat", .boat)
                            modeChip("Navigator", .navigator)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)

                        Group {
                            if mode == .boat {
                                // versionでidentityを変え、選択のたびに確実に反映する。
                                BoatSceneView(parts: BoatCustomization.currentParts)
                                    .id(version)
                            } else {
                                PhoenixNavigatorView(pose: navPose)
                            }
                        }
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                        Text("Drag to look around.")
                            .font(LFFont.label(13))
                            .foregroundStyle(LFColor.ink.opacity(0.5))
                            .padding(.horizontal, 24)
                            .padding(.top, 12)

                        if mode == .navigator {
                            // ポーズ切替(待機/歩く/掲げる/手を振る)。Web SailorStage 相当。
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(PhoenixPose.allCases) { pose in
                                        poseChip(pose)
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                            .padding(.top, 10)
                        }

                        if mode == .boat {
                            sailColorSection
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func modeChip(_ title: LocalizedStringKey, _ value: Mode) -> some View {
        let selected = mode == value
        return Button {
            mode = value
        } label: {
            Text(title)
                .font(LFFont.copy(15))
                .foregroundStyle(selected ? LFColor.paper : LFColor.ink)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(Capsule().fill(selected ? LFColor.ink : Color.clear))
                .overlay(Capsule().strokeBorder(LFColor.ink.opacity(selected ? 0 : 0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func poseChip(_ pose: PhoenixPose) -> some View {
        let selected = navPose == pose
        return Button {
            navPose = pose
            PhoenixPose.selected = pose   // 目的地の船上にも同じ姿で反映される
            Haptics.tap(.light)
        } label: {
            Text(pose.title)
                .font(LFFont.copy(15))
                .foregroundStyle(selected ? LFColor.paper : LFColor.ink)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(selected ? LFColor.ink : Color.clear))
                .overlay(Capsule().strokeBorder(LFColor.ink.opacity(selected ? 0 : 0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var sailColorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sail color")
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.5))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(BoatCustomization.sailColors) { option in
                    sailColorButton(option)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private func sailColorButton(_ option: SailColorOption) -> some View {
        let selected = BoatCustomization.selectedSailID == option.id
        return Button {
            BoatCustomization.selectSail(option.id)
            version += 1
            Haptics.tap(.light)
            RoomService.shared.pushProfileToAllRooms()
            PublicHarborService.shared.pushProfile()
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(option.color)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(LFColor.returnOrange, lineWidth: selected ? 3 : 0))

                Text(option.title)
                    .font(LFFont.label(11))
                    .foregroundStyle(LFColor.ink.opacity(selected ? 0.9 : 0.58))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? LFColor.returnOrange.opacity(0.07) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected ? LFColor.returnOrange : LFColor.ink.opacity(0.12),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
