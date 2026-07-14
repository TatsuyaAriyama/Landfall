import SwiftUI
import UniformTypeIdentifiers

/// 共有用に書き出したカード1枚分のPNG。ShareLinkにそのまま渡せる。
struct WrappedCardImage: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName { $0.fileName }
    }
}

/// カードViewをPNGへ書き出す。ImageRendererはメインアクター専用。
enum WrappedShare {

    /// 「Landfall-2026-05-card1.png」形式のファイル名。
    static func fileName(year: Int, month: Int, cardIndex: Int) -> String {
        String(format: "Landfall-%04d-%02d-card%d.png", year, month, cardIndex)
    }

    /// カードViewを3倍スケールでレンダリングし、PNGデータにする。
    @MainActor
    static func render(card: some View, fileName: String) -> WrappedCardImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        guard
            let cgImage = renderer.cgImage,
            let data = UIImage(cgImage: cgImage).pngData()
        else { return nil }
        return WrappedCardImage(data: data, fileName: fileName)
    }
}

/// カード下に置く共有ボタン。画像が未生成の間は薄く表示して待つ。
struct WrappedShareButton: View {
    let image: WrappedCardImage?

    var body: some View {
        if let image {
            ShareLink(item: image, preview: SharePreview(image.fileName)) {
                label
            }
        } else {
            label
                .opacity(0.35)
        }
    }

    private var label: some View {
        Text("共有")
            .font(LFFont.label(15))
            .foregroundStyle(LFColor.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .overlay {
                Capsule()
                    .stroke(LFColor.ink, lineWidth: 1.5)
            }
    }
}

#Preview {
    ZStack {
        LFColor.paper.ignoresSafeArea()
        VStack(spacing: 24) {
            WrappedShareButton(image: WrappedCardImage(
                data: Data(), fileName: WrappedShare.fileName(year: 2026, month: 5, cardIndex: 1)
            ))
            WrappedShareButton(image: nil)
        }
    }
}
