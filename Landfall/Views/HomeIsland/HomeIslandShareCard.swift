import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import SwiftUI
import UIKit

enum HomeIslandPhotoSaveState: Equatable {
    case idle
    case saving
    case saved
    case failed
}

enum HomeIslandPhotoLibrary {
    static func save(_ image: WrappedCardImage) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = image.fileName
                PHAssetCreationRequest.forAsset().addResource(
                    with: .photo,
                    data: image.data,
                    options: options
                )
            }
            return true
        } catch {
            return false
        }
    }
}

/// SceneKitの透明な空を画面と同じ色で合成し、見えていた構図をそのままSDR PNGへ書き出す。
@MainActor
enum HomeIslandPhotoExport {
    private static let skyColor = UIColor(rgb: 0x8BCFDB)
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let imageContext = CIContext(options: [
        .workingColorSpace: colorSpace,
        .outputColorSpace: colorSpace,
        .cacheIntermediates: false,
    ])
    private static let fallbackToneMapKernel = CIColorKernel(source: """
        kernel vec4 landfallToneMap(__sample pixel) {
            vec3 color = max(pixel.rgb, vec3(0.0));
            // Approximate CIToneMapHeadroom without crushing SDR reference white.
            // The lower segment preserves readable midtones; the upper segment
            // rolls the four-stop SceneKit headroom smoothly into SDR white.
            vec3 lower = color * (vec3(0.84) - vec3(0.064) * color);
            vec3 highlight = clamp(
                (color - vec3(1.0)) / vec3(3.0),
                vec3(0.0),
                vec3(1.0)
            );
            vec3 upper = vec3(0.776)
                + vec3(0.224) * (vec3(2.0) * highlight - highlight * highlight);
            color = mix(lower, upper, step(vec3(1.0), color));
            return vec4(color, pixel.a);
        }
        """)

    static func render(sceneImage: UIImage, capturedAt: Date) -> WrappedCardImage? {
        // SCNView.snapshot()はHDR値を持つ一方でHDR色空間として印付けされないため、
        // Core Imageの自動変換と重ねず、明示したheadroomから一度だけSDRへ圧縮する。
        guard let scene = CIImage(image: sceneImage), !scene.extent.isEmpty
        else { return nil }

        let toneMapped: CIImage
        if #available(iOS 18.0, *) {
            let filter = CIFilter.toneMapHeadroom()
            filter.inputImage = scene
            filter.sourceHeadroom = 4
            filter.targetHeadroom = 1
            toneMapped = filter.outputImage ?? scene
        } else if let fallback = fallbackToneMapKernel?.apply(
            extent: scene.extent,
            arguments: [scene]
        ) {
            toneMapped = fallback
        } else {
            toneMapped = scene
        }

        let background = CIImage(color: CIColor(color: skyColor))
            .cropped(to: scene.extent)
        let photo = toneMapped.composited(over: background)
        guard let cgImage = imageContext.createCGImage(
            photo,
            from: photo.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ), let data = UIImage(cgImage: cgImage).pngData()
        else { return nil }
        return WrappedCardImage(data: data, fileName: fileName(for: capturedAt))
    }

    private static func fileName(for date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "KeelMira-Island-%04d-%02d-%02d-%02d%02d%02d.png",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }
}

/// 従来のSNS向け4:5共有カード。写真保存用の元画像とは分けて生成する。
struct HomeIslandShareCard: View {
    static let size = CGSize(width: 390, height: 488)

    let sceneImage: UIImage
    let capturedAt: Date

    var body: some View {
        ZStack {
            Image(uiImage: sceneImage)
                .resizable()
                .scaledToFill()
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.38), location: 0),
                    .init(color: .clear, location: 0.30),
                    .init(color: .clear, location: 0.72),
                    .init(color: .black.opacity(0.36), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                masthead
                Spacer()
                bottomMetadata
            }
            .padding(18)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(uiColor: VoyageSceneKit.seaDeep))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .environment(\.lfFixedType, true)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, AppLanguage.current.locale)
    }

    private var masthead: some View {
        HStack(spacing: 10) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
            Text("MY ISLAND")
                .font(LFFont.labelFixed(10))
                .tracking(1.7)
            Spacer()
            Text(verbatim: "KeelMira")
                .font(LFFont.copyFixed(13))
                .tracking(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(.black.opacity(0.34), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private var bottomMetadata: some View {
        HStack(alignment: .bottom) {
            Text(verbatim: LF.fullDate(capturedAt))
                .font(LFFont.labelFixed(9))
                .tracking(0.8)
                .foregroundStyle(LFColor.returnOrange)
                .shadow(color: .black.opacity(0.38), radius: 2, y: 1)
            Spacer()
            if let qr = LandfallLink.qrImage(for: LandfallLink.sharePromotionURL) {
                Image(uiImage: qr)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)
            }
        }
    }

    static func fileName(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "KeelMira-My-Island-%04d-%02d-%02d.png",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

/// 撮影結果だけを大きく見せる、説明文のない確認画面。
struct HomeIslandShareSheet: View {
    let photo: WrappedCardImage
    let shareCard: WrappedCardImage?
    let saveState: HomeIslandPhotoSaveState
    let onRetake: () -> Void
    let onClose: () -> Void

    @State private var showingShareCard = false

    private var previewImage: UIImage? {
        UIImage(data: photo.data)
    }

    var body: some View {
        ZStack {
            (showingShareCard ? LFColor.paper : Color.black)
                .ignoresSafeArea()

            if showingShareCard {
                shareCardPreview
            } else if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack {
                    if showingShareCard {
                        Button {
                            showingShareCard = false
                            Haptics.tap(.light)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(LFColor.ink)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.78), in: Circle())
                        }
                        .buttonStyle(LFPressableButtonStyle())
                        .accessibilityLabel(Text("Back"))
                    }
                    Spacer()
                    if !showingShareCard {
                        saveStateIndicator
                    }
                }
                .padding(.horizontal, 18)
                .safeAreaPadding(.top, 10)

                Spacer()

                HStack(spacing: 10) {
                    if showingShareCard {
                        if let shareCard {
                            ShareLink(item: shareCard, preview: SharePreview(shareCard.fileName)) {
                                primaryShareButton
                            }
                            .simultaneousGesture(TapGesture().onEnded { Haptics.success() })
                            .accessibilityLabel(Text("Share"))
                        }
                    } else {
                        controlButton(
                            symbol: "arrow.counterclockwise",
                            accessibilityLabel: "Retake"
                        ) {
                            onRetake()
                        }

                        Button {
                            showingShareCard = true
                            Haptics.tap(.light)
                        } label: {
                            primaryShareButton
                        }
                        .buttonStyle(LFPressableButtonStyle())
                        .disabled(shareCard == nil)
                        .accessibilityLabel(Text("Share"))
                    }

                    controlButton(symbol: "xmark", accessibilityLabel: "Close photo") {
                        onClose()
                    }
                }
                .padding(7)
                .background(.black.opacity(0.56), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
                .safeAreaPadding(.bottom, 14)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var shareCardPreview: some View {
        if let shareCard,
           let image = UIImage(data: shareCard.data) {
            GeometryReader { geometry in
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(
                        width: max(0, geometry.size.width - 36),
                        height: max(0, geometry.size.height - 150)
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
                    .accessibilityLabel(Text("Island share card"))
            }
        } else {
            ProgressView()
                .tint(LFColor.ink)
        }
    }

    private var primaryShareButton: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(.black.opacity(0.88))
            .frame(width: 58, height: 58)
            .background(.white, in: Circle())
    }

    @ViewBuilder
    private var saveStateIndicator: some View {
        switch saveState {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView()
                .tint(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.42), in: Circle())
                .accessibilityLabel(Text("Saving photo"))
        case .saved:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.42), in: Circle())
                .accessibilityLabel(Text("Photo saved"))
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.red.opacity(0.72), in: Circle())
                .accessibilityLabel(Text("Photo could not be saved"))
        }
    }

    private func controlButton(
        symbol: String,
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(.black.opacity(0.56), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
