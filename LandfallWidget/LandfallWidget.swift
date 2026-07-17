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

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            default: small
            }
        }
        .containerBackground(Color.wTeal, for: .widget)
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct LandfallWidgetBundle: WidgetBundle {
    var body: some Widget { LandfallWidget() }
}
