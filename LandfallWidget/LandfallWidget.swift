import WidgetKit
import SwiftUI

// MARK: - 色(ウィジェットは自己完結。アプリのLFColorは共有しない)
private extension Color {
    init(h: UInt) {
        self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: 1)
    }
    static let wTeal = Color(h: 0x184A40)
    static let wSand = Color(h: 0xEADEBD)
    static let wSun = Color(h: 0xFFD84D)
    static let wSea = Color(h: 0x5DCAA5)
}

private let appGroup = "group.com.tatsuyaariyama.Landfall"

// MARK: - データ

struct LandfallEntry: TimelineEntry {
    let date: Date
    let month: Int
    let studied: Int
    let rested: Int
}

struct Provider: TimelineProvider {
    private var store: UserDefaults? { UserDefaults(suiteName: appGroup) }

    func placeholder(in context: Context) -> LandfallEntry {
        LandfallEntry(date: Date(), month: 7, studied: 8, rested: 20)
    }
    func getSnapshot(in context: Context, completion: @escaping (LandfallEntry) -> Void) {
        completion(currentEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LandfallEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date().addingTimeInterval(3 * 3600)
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }
    private func currentEntry() -> LandfallEntry {
        let s = store
        let month = s?.object(forKey: "w_month") as? Int ?? Calendar.current.component(.month, from: Date())
        return LandfallEntry(date: Date(), month: month,
                             studied: s?.integer(forKey: "w_studied") ?? 0,
                             rested: s?.integer(forKey: "w_rested") ?? 0)
    }
}

// MARK: - View

struct LandfallWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LandfallEntry

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    var body: some View {
        content
            // ロック画面(accessory)はモノクロ/ヴィブラント描画なので固定色は効かない。
            // 地は clear にし、ホーム画面(system)だけティール地にする。
            .containerBackground(for: .widget) {
                isAccessory ? Color.clear : Color.wTeal
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: - ロック画面(accessory)

    /// 円形。学と休を対等に二段で。比率ゲージにはしない(学>休 の含意を作らない)。
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                accessoryCount("学", entry.studied)
                accessoryCount("休", entry.rested)
            }
        }
    }

    private func accessoryCount(_ label: String, _ n: Int) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 11))
            Text("\(n)").font(.system(size: 16, weight: .medium)).monospacedDigit()
        }
    }

    /// 横長。月・学/休・やめた0。数字は同じ大きさで並べる。
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(entry.month)月のあなた")
                .font(.system(size: 12, weight: .medium))
                .widgetAccentable()
            HStack(spacing: 12) {
                accessoryDays("学", entry.studied)
                accessoryDays("休", entry.rested)
            }
            Text("やめた回数 0").font(.system(size: 11)).opacity(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accessoryDays(_ label: String, _ n: Int) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 12))
            Text("\(n)").font(.system(size: 18, weight: .medium)).monospacedDigit()
            Text("日").font(.system(size: 11))
        }
    }

    /// 一行(時計の隣)。督促ではなく静かな事実として。
    private var inline: some View {
        Label {
            Text("学\(entry.studied) 休\(entry.rested)・やめた0")
        } icon: {
            Image(systemName: "sailboat")
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(entry.month)月のあなた")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.wSand.opacity(0.9))
            Spacer(minLength: 0)
            countRow(entry.studied, "学んだ", .wSun)
            Spacer().frame(height: 8)
            countRow(entry.rested, "休んだ", .wSea)
            Spacer(minLength: 0)
            Text("やめた回数 0").font(.system(size: 12, weight: .regular)).foregroundStyle(Color.wSand.opacity(0.7))
        }
    }

    private var medium: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(entry.month)月のあなた")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.wSand.opacity(0.9))
                countRow(entry.studied, "学んだ", .wSun)
                countRow(entry.rested, "休んだ", .wSea)
                Text("やめた回数 0").font(.system(size: 12)).foregroundStyle(Color.wSand.opacity(0.7))
            }
            Spacer(minLength: 0)
            Text("休んでも、\nあなたはここにいる。")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.wSand)
                .multilineTextAlignment(.trailing).fixedSize()
        }
    }

    private func countRow(_ n: Int, _ label: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(n)").font(.system(size: 34, weight: .medium)).foregroundStyle(color).monospacedDigit()
            Text("日").font(.system(size: 14, weight: .regular)).foregroundStyle(color)
            Text(label).font(.system(size: 15, weight: .regular)).foregroundStyle(.white)
        }
    }
}

// MARK: - Widget

struct LandfallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LandfallWidget", provider: Provider()) { entry in
            LandfallWidgetView(entry: entry)
        }
        .configurationDisplayName("Landfall")
        .description("今月の学んだ日・休んだ日を同じ大きさで。")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

@main
struct LandfallWidgetBundle: WidgetBundle {
    var body: some Widget { LandfallWidget() }
}
