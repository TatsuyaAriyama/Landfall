import Foundation
import SwiftUI

/// 外から来たリンクを、画面に届ける小さな伝令。
/// 招待リンク(landfall://join?code=XXXXXX)を受けたら港タブへ運び、コードを渡す。
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    private init() {}

    /// 港タブで受け取られるまで持っておく招待コード。受け取り側が nil に戻す。
    @Published var pendingJoinCode: String?
    /// 港タブへ切り替える合図。
    @Published var wantsHarborTab = false

    /// 受け取ったURLを処理できたら true。
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let code = LandfallLink.joinCode(from: url) else { return false }
        pendingJoinCode = code
        wantsHarborTab = true
        return true
    }
}
