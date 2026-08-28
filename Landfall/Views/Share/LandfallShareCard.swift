import SceneKit
import SwiftUI

/// 上陸した瞬間にだけ書き出せる、3Dの島を背景にした記念カード。
struct LandfallShareCard: View {
    let destination: Destination
    let minutes: Int
    let worldImage: UIImage

    var body: some View {
        ZStack {
            Image(uiImage: worldImage)
                .resizable()
                .scaledToFill()
                .frame(width: LFMetrics.cardSize.width, height: LFMetrics.cardSize.height)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.36), location: 0),
                    .init(color: Color.clear, location: 0.34),
                    .init(color: Color(VoyageSceneKit.seaDeep).opacity(0.18), location: 0.60),
                    .init(color: Color(VoyageSceneKit.seaDeep).opacity(0.90), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    HStack(spacing: 9) {
                        TileSymbolView(
                            symbol: .sailboat,
                            fg: LFColor.harborSand,
                            bg: Color(VoyageSceneKit.seaDeep)
                        )
                        .frame(width: 26, height: 26)
                        Text(verbatim: "KeelMira")
                            .font(LFFont.copy(16))
                            .foregroundStyle(LFColor.harborSand)
                    }
                    Spacer()
                    Text("LANDFALL")
                        .font(LFFont.label(10))
                        .tracking(2.1)
                        .foregroundStyle(LFColor.returnOrange)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Voyage completed")
                            .font(LFFont.label(11))
                            .tracking(1.1)
                    }
                    .foregroundStyle(LFColor.returnOrange)

                    Text(verbatim: destination.name)
                        .font(LFFont.label(22))
                        .tracking(1.1)
                        .foregroundStyle(LFColor.returnOrange)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Rectangle()
                        .fill(LFColor.harborSand.opacity(0.22))
                        .frame(height: 1)

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Landed on")
                                .font(LFFont.label(10))
                                .tracking(0.9)
                                .foregroundStyle(LFColor.harborSand.opacity(0.48))
                            Text(verbatim: LF.fullDate(destination.achievedAt ?? Date()))
                                .font(LFFont.copy(14))
                                .foregroundStyle(LFColor.harborSand.opacity(0.92))
                        }

                        Spacer()

                        if minutes > 0 {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Time at sea")
                                    .font(LFFont.label(10))
                                    .tracking(0.9)
                                    .foregroundStyle(LFColor.harborSand.opacity(0.48))
                                Text(verbatim: LF.duration(minutes: minutes))
                                    .font(LFFont.copy(14))
                                    .foregroundStyle(LFColor.harborSand.opacity(0.92))
                            }
                        }
                    }
                }
                .padding(22)
                .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(LFColor.harborSand.opacity(0.16), lineWidth: 1)
                }
            }
            .padding(24)
        }
        .frame(width: LFMetrics.cardSize.width, height: LFMetrics.cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .background(Color(VoyageSceneKit.seaDeep))
        .environment(\.lfFixedType, true)
    }
}

struct LandfallShareSheet: View {
    let destination: Destination
    let minutes: Int

    @Environment(\.dismiss) private var dismiss
    @State private var artifact: LandfallShareArtifact?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Landfall card")
                        .font(LFFont.copy(20))
                        .foregroundStyle(LFColor.ink)
                    Text("Only available at the moment you go ashore.")
                        .font(LFFont.label(11))
                        .foregroundStyle(LFColor.ink.opacity(0.48))
                }
                Spacer()
                Button("Close") { dismiss() }
                    .font(LFFont.label(15))
                    .foregroundStyle(LFColor.ink.opacity(0.62))
            }
            .padding(.horizontal, LFMetrics.cardPadding)
            .padding(.top, 22)
            .padding(.bottom, 12)

            GeometryReader { geometry in
                let scale = min(
                    (geometry.size.width - 42) / LFMetrics.cardSize.width,
                    (geometry.size.height - 28) / LFMetrics.cardSize.height,
                    1
                )

                Group {
                    if let artifact {
                        LandfallShareCard(
                            destination: destination,
                            minutes: minutes,
                            worldImage: artifact.worldImage
                        )
                        .scaleEffect(scale)
                        .frame(
                            width: LFMetrics.cardSize.width * scale,
                            height: LFMetrics.cardSize.height * scale
                        )
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(LFColor.returnOrange)
                            Text("Charting the island…")
                                .font(LFFont.label(12))
                                .foregroundStyle(LFColor.ink.opacity(0.48))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(LFColor.ink.opacity(0.05))

            Group {
                if let image = artifact?.shareImage {
                    ShareLink(item: image, preview: SharePreview(image.fileName)) {
                        shareLabel(ready: true)
                    }
                    .simultaneousGesture(TapGesture().onEnded { Haptics.success() })
                } else {
                    shareLabel(ready: false)
                }
            }
            .padding(.horizontal, LFMetrics.cardPadding)
            .padding(.vertical, 18)
        }
        .background(LFColor.paper)
        .presentationDetents([.large])
        .task {
            guard artifact == nil else { return }
            artifact = LandfallShareRenderer.render(
                destination: destination,
                minutes: minutes
            )
        }
    }

    private func shareLabel(ready: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "square.and.arrow.up")
            Text(ready ? "Save or share" : "Preparing…")
        }
        .font(LFFont.copy(17))
        .foregroundStyle(LFColor.paper)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(ready ? LFColor.ink : LFColor.ink.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
    }
}

struct LandfallShareArtifact {
    let worldImage: UIImage
    let shareImage: WrappedCardImage
}

@MainActor
enum LandfallShareRenderer {
    static func render(destination: Destination, minutes: Int) -> LandfallShareArtifact? {
        let worldImage = renderWorld()
        guard let shareImage = WrappedShare.render(
            card: LandfallShareCard(
                destination: destination,
                minutes: minutes,
                worldImage: worldImage
            ),
            fileName: fileName(destination)
        ) else { return nil }
        return LandfallShareArtifact(worldImage: worldImage, shareImage: shareImage)
    }

    private static func renderWorld() -> UIImage {
        let scale: CGFloat = 3
        let renderTime: TimeInterval = 2.4
        let size = CGSize(
            width: LFMetrics.cardSize.width * scale,
            height: LFMetrics.cardSize.height * scale
        )
        let view = SCNView(frame: CGRect(origin: .zero, size: size))
        view.contentScaleFactor = 1
        view.scene = VoyageSceneKit.makeLandfallScene(
            oceanTime: Float(renderTime),
            nativeMetalRollout: .stillImage
        )
        view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
        view.backgroundColor = VoyageSceneKit.nightBG
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.sceneTime = renderTime
        if let scene = view.scene {
            view.prepare(scene, shouldAbortBlock: nil)
        }
        return view.snapshot()
    }

    private static func fileName(_ destination: Destination) -> String {
        let date = destination.achievedAt ?? Date()
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "KeelMira-Landfall-%04d-%02d-%02d.png",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
