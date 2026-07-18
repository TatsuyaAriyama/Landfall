import FirebaseAppCheck
import FirebaseCore
import Foundation

/// App Check のプロバイダ工場。
///
/// App Check は「本物のこのアプリからのアクセスか」を裏で証明し、
/// 盗んだ設定値だけを使った外部からのバックエンド濫用(なりすまし・総当たり)を防ぐ。
///
/// - 本番(実機): App Attest(Secure Enclave による端末+アプリの証明)。
/// - DEBUG(シミュレータ/開発機): デバッグプロバイダ。起動ログに出るデバッグトークンを
///   Firebase コンソールに登録すると検証が通る。
///
/// 注意: 実際に濫用を「遮断」するには Firebase コンソールで App Check を有効化し、
/// Firestore/Auth で **enforcement を ON** にする必要がある(それまでは監視のみ)。
/// enforcement が OFF の間は、未登録でも通常の通信は妨げられない(安全に先行導入できる)。
final class LandfallAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        // 配備ターゲットは iOS 17 なので App Attest は常に利用可能。
        return AppAttestProvider(app: app)
        #endif
    }
}
