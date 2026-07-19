import SwiftUI

/// 入港証。港の招待を「6文字を手で打たせる」から「一枚渡す」に変える。
/// 港名・合鍵(コード)・QRを1枚に収め、画像として送れる。
/// 固定寸法の絵はがきなので、文字サイズ・外観設定の影響を受けない。
struct InvitePassCard: View {
    let roomName: String
    let code: String

    private var inviteURL: URL { LandfallLink.invite(code: code) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Harbor pass")
                .font(LFFont.labelFixed(15))
                .tracking(2)
                .foregroundStyle(LFColor.harborSand.opacity(0.55))

            Text(verbatim: roomName)
                .font(LFFont.copyFixed(26))
                .foregroundStyle(LFColor.harborSand)
                .lineLimit(2)
                .padding(.top, 10)

            Spacer(minLength: 28)

            HStack(alignment: .bottom, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Harbor code")
                        .font(LFFont.labelFixed(13))
                        .foregroundStyle(LFColor.harborSand.opacity(0.55))
                    Text(verbatim: code)
                        .font(LFFont.numberFixed(40))
                        .tracking(6)
                        .foregroundStyle(LFColor.sunYellow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                // 行き先が決まっていないうちはQRを描かない(死んだQRを配らない)。
                if LandfallLink.canShowQR, let qr = LandfallLink.qrImage(for: inviteURL) {
                    qrBlock(qr)
                }
            }

            Spacer(minLength: 24)

            Text("Open this harbor with the code above.")
                .font(LFFont.copyFixed(15))
                .foregroundStyle(LFColor.harborSand.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if let host = LandfallLink.displayHost {
                Text(verbatim: host)
                    .font(LFFont.labelFixed(13))
                    .foregroundStyle(LFColor.harborSand.opacity(0.45))
                    .padding(.top, 8)
            }

            Spacer(minLength: 20)

            Text(verbatim: "Landfall-StudyLog")
                .font(LFFont.labelFixed(13))
                .foregroundStyle(LFColor.harborSand.opacity(0.4))
        }
        .padding(LFMetrics.cardPadding)
        .frame(width: LFMetrics.cardSize.width, alignment: .topLeading)
        .frame(minHeight: 460, alignment: .topLeading)
        .background(harborGround)
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .environment(\.lfFixedType, true)
        .environment(\.colorScheme, .light)
    }

    /// QRは「濃い図形 / 明るい地」でないと読めないので、必ず明るい下敷きに置く。
    private func qrBlock(_ qr: UIImage) -> some View {
        Image(uiImage: qr)
            .resizable()
            .interpolation(.none)   // QRは補間するとモジュールが滲んで読めなくなる。
            .frame(width: 84, height: 84)
            .padding(10)            // 静穏域。これが無いと読み取り率が落ちる。
            .background(LFColor.harborSand)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 港の地。サインイン画面と同じ凪いだ水面の語彙をフラットで敷く。
    /// ブランドマークは左下に置くので、水面は右下へ逃がして文字と重ねない。
    private var harborGround: some View {
        ZStack(alignment: .bottomTrailing) {
            LFColor.harborTeal
            VStack(alignment: .trailing, spacing: 12) {
                Capsule(style: .continuous)
                    .fill(LFColor.harborSand.opacity(0.16))
                    .frame(width: 150, height: 7)
                Capsule(style: .continuous)
                    .fill(LFColor.harborSand.opacity(0.11))
                    .frame(width: 92, height: 6)
            }
            .padding(.trailing, LFMetrics.cardPadding)
            .padding(.bottom, 30)
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    InvitePassCard(roomName: "夜の自習室", code: "K7M2QP")
}
