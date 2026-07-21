import SwiftUI

/// 入港証を見せて配るシート。画像でも、文章+リンクでも渡せる。
struct InvitePassSheet: View {
    let roomName: String
    let code: String

    @Environment(\.dismiss) private var dismiss
    @State private var image: WrappedCardImage?

    /// 文章で誘うときの本文。リンクが無い状態でもコードだけで成立する文にする。
    private var inviteText: String {
        let base = String(
            format: String(localized: "Come sail with me in \"%@\" on Landfall. Harbor code: %@"),
            roomName, code
        )
        // 未インストールの人向けに入手ページを添える(コードは手入力)。公開前は付けない。
        guard let download = LandfallLink.downloadURL else { return base }
        return base + "\n" + download.absoluteString
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geo in
                let scale = min((geo.size.width - 48) / LFMetrics.cardSize.width, 1)
                ScrollView {
                    InvitePassCard(roomName: roomName, code: code)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: LFMetrics.cardSize.width * scale)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
                .background(LFColor.ink.opacity(0.06))
            }

            VStack(spacing: 12) {
                if let image {
                    ShareLink(item: image, preview: SharePreview(image.fileName)) {
                        primaryLabel("Send the pass")
                    }
                    .simultaneousGesture(TapGesture().onEnded { Haptics.success() })
                } else {
                    primaryLabel("Preparing…").opacity(0.5)
                }

                ShareLink(item: inviteText) {
                    Text("Send as text")
                        .font(LFFont.label(15))
                        .foregroundStyle(LFColor.ink.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, LFMetrics.cardPadding)
            .padding(.bottom, 20)
        }
        .background(LFColor.paper)
        .presentationDetents([.large])
        .onAppear { render() }
    }

    private var header: some View {
        HStack {
            Text("Harbor pass")
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
            Spacer()
            Button("Close") { dismiss() }
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink.opacity(0.6))
        }
        .padding(.horizontal, LFMetrics.cardPadding)
        .padding(.top, 24)
    }

    private func primaryLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(LFFont.copy(18))
            .foregroundStyle(LFColor.paper)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(LFColor.ink)
            .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
    }

    @MainActor
    private func render() {
        image = WrappedShare.render(
            card: InvitePassCard(roomName: roomName, code: code),
            fileName: "Landfall-harbor-\(code).png"
        )
    }
}
