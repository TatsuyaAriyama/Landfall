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

    /// アプリの入口。例: URL(string: "https://apps.apple.com/jp/app/idXXXXXXXXX")
    /// nil のあいだは共有画像にQR・URLを描かない。
    static let site: URL? = {
        #if DEBUG
        // 動作確認用: LANDFALL_SITE=https://… で行き先を差し替えられる。
        if let raw = ProcessInfo.processInfo.environment["LANDFALL_SITE"],
           let url = URL(string: raw) {
            return url
        }
        #endif
        return nil
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

    /// 港の招待リンク。Webの入口があればそちら(未インストールでも辿り着ける)、
    /// 無ければカスタムスキーム(インストール済みの人だけ開ける)。
    static func invite(code: String) -> URL {
        let cleaned = normalize(code)
        if let site {
            return site.appendingPathComponent("j").appendingPathComponent(cleaned)
        }
        return URL(string: "\(scheme)://join?code=\(cleaned)")!
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
