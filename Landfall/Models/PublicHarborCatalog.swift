import SwiftUI

/// パブリックの港(公式)。カタログはアプリに内蔵し、Firestore には参加と潮位だけを置く。
/// 港そのものを運営が用意する=部屋の乱立・命名の荒れが構造的に起きない。
/// 公開面に個人は並べない。見えるのは「港ぜんたいの潮」だけ。
struct PublicHarbor: Identifiable, Hashable {
    /// Firestore のドキュメントキー。変更禁止(参加・潮位がこのIDに紐づく)。
    let slug: String
    let title: LocalizedStringKey
    let tagline: LocalizedStringKey
    let style: TileStyle
    let symbol: TileSymbol

    var id: String { slug }

    static func == (lhs: PublicHarbor, rhs: PublicHarbor) -> Bool { lhs.slug == rhs.slug }
    func hash(into hasher: inout Hasher) { hasher.combine(slug) }

    /// 公式の5港。増減はアプリ更新で行う(スラッグは Firestore ルールの許可リストと一致させること)。
    static let all: [PublicHarbor] = [
        PublicHarbor(
            slug: "language",
            title: "Languages",
            tagline: "Miss a day, and the words still wait for you.",
            style: .seaGreen, symbol: .compass
        ),
        PublicHarbor(
            slug: "certification",
            title: "Certifications",
            tagline: "A long voyage to the pass line, never alone.",
            style: .midnight, symbol: .lighthouse
        ),
        PublicHarbor(
            slug: "student",
            title: "Students",
            tagline: "A harbor you can always come back to, all through school.",
            style: .coral, symbol: .phoenix
        ),
        PublicHarbor(
            slug: "reading",
            title: "Reading",
            tagline: "Books you read and books you piled — both belong here.",
            style: .violet, symbol: .book
        ),
        PublicHarbor(
            slug: "making",
            title: "Making",
            tagline: "The days your hands rested still count as making.",
            style: .sunYellow, symbol: .pen
        ),
    ]

    static func by(slug: String) -> PublicHarbor? {
        all.first { $0.slug == slug }
    }
}
