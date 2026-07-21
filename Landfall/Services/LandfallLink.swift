import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

/// アプリへの導線(URL)とQRコードの一元管理。
///
/// **重要**: 共有画像は一度出回ると回収できない。行き先が無いQRを焼き込むと、
/// 未来の全ての共有物が死んだQRを抱えることになる。
/// そのため `site` が未設定のあいだは、QRもURLも**一切描かない**設計にしてある。
/// App Store公開URL(または独自ドメイン)が決まったら、ここに1行入れるだけで
/// カードと入港証の両方にQRが出るようになる。
enum LandfallLink {

    // MARK: - 設定するのはここだけ

    /// App Store の数値ID。App Store Connect でアプリを作成した時点で採番される
    /// (審査中でも確認できる)。App情報 → 一般情報 → 「Apple ID」。
    /// **公開されたら**この2箇所を埋めるだけで、共有カードと入港証にQR・リンクが出る:
    ///   1. `appStoreID` に数値IDを入れる
    ///   2. `isPubliclyAvailable` を true にする(= 審査通過・配信開始後)
    /// ※ 公開前に true にすると、まだ開けないURLのQRが共有画像に焼き込まれてしまう。
    static let appStoreID: String? = nil            // 例: "6612345678"
    static let isPubliclyAvailable = false          // 配信開始後に true

    /// アプリの入口。公開後は App Store のページ、それまでは nil(QR/URLを描かない)。
    static let site: URL? = {
        #if DEBUG
        // 動作確認用: LANDFALL_SITE=https://… で行き先を差し替えられる。
        if let raw = ProcessInfo.processInfo.environment["LANDFALL_SITE"],
           let url = URL(string: raw) {
            return url
        }
        #endif
        guard isPubliclyAvailable, let id = appStoreID, !id.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }()

    /// アプリが入っている端末で直接開くためのカスタムURLスキーム。
    /// ドメインもApp Store IDも要らないので、これは今日から使える。
    static let scheme = "landfall"

    // MARK: - 導線があるか

    /// 共有画像にQRを載せてよいか。
    static var canShowQR: Bool { site != nil }

    /// 画像に添える短い表記(QRの下に置く)。スキームだけの状態では出さない。
    static var displayHost: String? {
        guard let host = site?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - 港の招待

    /// アプリを入手できるページ(共有物のQR先)。公開後のみ。
    static var downloadURL: URL? { site }

    /// 港の招待の deep link。インストール済みの端末で開くと参加シートが出る。
    /// 未インストールの人向けには App Store の downloadURL を別に見せ、6文字コードは手入力
    /// (App Store のURLは経路にコードを載せられないため)。真の universal link には
    /// 自前ドメイン + apple-app-site-association のホストが要る(未整備)。
    static func invite(code: String) -> URL {
        URL(string: "\(scheme)://join?code=\(normalize(code))")!
    }

    /// 受け取ったURLから港のコードを取り出す。landfall://join?code=XXXXXX と https://…/j/XXXXXX の両方。
    static func joinCode(from url: URL) -> String? {
        if url.scheme == scheme, url.host == "join" {
            let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
            return code.map(normalize).flatMap { $0.isEmpty ? nil : $0 }
        }
        // https://<site>/j/<CODE>
        if let site, url.host == site.host {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2, parts[parts.count - 2] == "j" {
                let code = normalize(parts[parts.count - 1])
                return code.isEmpty ? nil : code
            }
        }
        return nil
    }

    /// 招待コードの正規化(大文字・空白除去)。入力ゆれを吸収する。
    static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    // MARK: - QR

    /// QRコード画像。読み取りやすさのため常に「濃い図形 / 明るい地」で作る
    /// (暗い配色のカードでは、明るい下敷きの上に置くこと)。
    /// ImageRendererから呼ばれるので決定的で、失敗したら nil を返して描画側が省く。
    static func qrImage(for url: URL, pixelScale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        // M = 15%の誤り訂正。小さく刷っても読める余裕を持たせる。
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: pixelScale, y: pixelScale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
