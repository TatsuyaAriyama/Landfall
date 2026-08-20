import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Widget palette

private extension Color {
    init(h: UInt) {
        self.init(
            .sRGB,
            red: Double((h >> 16) & 0xFF) / 255,
            green: Double((h >> 8) & 0xFF) / 255,
            blue: Double(h & 0xFF) / 255,
            opacity: 1
        )
    }

    static let wNight = Color(h: 0x123830)
    static let wTeal = Color(h: 0x184A40)
    static let wSand = Color(h: 0xEADEBD)
    static let wCoral = Color(h: 0xF0997B)
    static let wOrange = Color(h: 0xF5822A)
    static let wSun = Color(h: 0xF3C065)
    static let wSea = Color(h: 0x5DCAA5)
}

// MARK: - Timeline

struct LandfallEntry: TimelineEntry {
    let date: Date
    let month: Int
    let studied: Int
    let rested: Int
    let todayMinutes: Int
    let items: [KeelMiraWidgetItem]
    let timer: KeelMiraWidgetTimer
}

struct Provider: TimelineProvider {
    private var store: UserDefaults { KeelMiraWidgetStore.defaults }

    func placeholder(in context: Context) -> LandfallEntry {
        let sampleNames = KeelMiraWidgetCopy.sampleItemNames
        return LandfallEntry(
            date: Date(),
            month: 7,
            studied: 8,
            rested: 12,
            todayMinutes: 42,
            items: [
                KeelMiraWidgetItem(id: "preview-reading", name: sampleNames.0, styleToken: "midnight", symbolToken: "book"),
                KeelMiraWidgetItem(id: "preview-writing", name: sampleNames.1, styleToken: "coral", symbolToken: "pen"),
                KeelMiraWidgetItem(id: "preview-study", name: sampleNames.2, styleToken: "seaGreen", symbolToken: "compass"),
            ],
            timer: KeelMiraWidgetTimer(
                startedAt: Date().addingTimeInterval(-25 * 60).timeIntervalSince1970,
                itemID: "preview-reading",
                itemName: sampleNames.0,
                timerMode: "free",
                pomodoroStartElapsed: 0,
                breakSeconds: 0,
                breakStartedAt: 0
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LandfallEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LandfallEntry>) -> Void) {
        let now = Date()
        let next: Date
        if KeelMiraWidgetStore.timer.isActive {
            // 時計自体はText(.timer)をシステムが進める。タイムラインは状態の再照合だけ。
            next = now.addingTimeInterval(30 * 60)
        } else {
            next = Calendar.current.nextDate(
                after: now,
                matching: DateComponents(hour: 0, minute: 0),
                matchingPolicy: .nextTime
            ) ?? now.addingTimeInterval(3 * 60 * 60)
        }
        completion(Timeline(entries: [currentEntry(at: now)], policy: .after(next)))
    }

    private func currentEntry(at date: Date = Date()) -> LandfallEntry {
        LandfallEntry(
            date: date,
            month: store.object(forKey: "w_month") as? Int
                ?? Calendar.current.component(.month, from: date),
            studied: store.integer(forKey: "w_studied"),
            rested: store.integer(forKey: "w_rested"),
            todayMinutes: store.integer(forKey: KeelMiraWidgetStore.Key.todayMinutes),
            items: KeelMiraWidgetStore.workItems,
            timer: KeelMiraWidgetStore.timer
        )
    }
}

// MARK: - Root view

struct LandfallWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: LandfallEntry

    private var isAccessory: Bool {
        family == .accessoryCircular
            || family == .accessoryRectangular
            || family == .accessoryInline
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isAccessory {
                    Color.clear
                } else {
                    WidgetVoyageStill(renderingMode: renderingMode)
                }
            }
            .widgetURL(URL(string: "keelmira://home"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: Home Screen

    private var small: some View {
        Group {
            if entry.timer.isActive {
                activeSmall
            } else {
                idleSmall
            }
        }
        .foregroundStyle(Color.wSand)
    }

    private var activeSmall: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.timer.isResting ? Color.wSun : Color.wSea)
                    .frame(width: 7, height: 7)
                Text(entry.timer.isResting ? KeelMiraWidgetCopy.resting : KeelMiraWidgetCopy.sailing)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.wSand.opacity(0.76))

            Text(entry.timer.itemName.isEmpty ? KeelMiraWidgetCopy.working : entry.timer.itemName)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .padding(.top, 7)

            timerText(fontSize: 29)
                .padding(.top, 2)

            Spacer(minLength: 5)

            HStack(spacing: 8) {
                Button(intent: ToggleKeelMiraBreakIntent()) {
                    Image(systemName: entry.timer.isResting ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityLabel(entry.timer.isResting ? KeelMiraWidgetCopy.resumeVoyage : KeelMiraWidgetCopy.takeABreak)

                Button(intent: MakeKeelMiraLandfallIntent()) {
                    Image(systemName: "flag.checkered")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityLabel(KeelMiraWidgetCopy.landfall)
            }
            .font(.system(size: 13, weight: .semibold))
            .tint(Color.wSand)
            .buttonStyle(WidgetActionButtonStyle())
            .frame(height: 34)
        }
    }

    private var idleSmall: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "KeelMira")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.wSand.opacity(0.72))

            Spacer(minLength: 5)

            Text(KeelMiraWidgetCopy.todaysVoyage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.wSand.opacity(0.7))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(entry.todayMinutes)")
                    .font(.system(size: 31, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(KeelMiraWidgetCopy.minuteUnit)
                    .font(.system(size: 12, weight: .medium))
            }

            Spacer(minLength: 6)

            if let item = preferredItem {
                Button(intent: StartKeelMiraVoyageIntent(item: item)) {
                    HStack(spacing: 6) {
                        WidgetItemSymbol(token: item.symbolToken)
                            .frame(width: 17, height: 17)
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "wind")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
                .tint(Color.wSand)
                .buttonStyle(WidgetActionButtonStyle())
                .accessibilityLabel(KeelMiraWidgetCopy.setSail(with: item.name))
            } else {
                Text(KeelMiraWidgetCopy.addItemShort)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.wSand.opacity(0.72))
            }
        }
    }

    private var medium: some View {
        Group {
            if entry.timer.isActive {
                activeMedium
            } else {
                idleMedium
            }
        }
        .foregroundStyle(Color.wSand)
    }

    private var activeMedium: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(entry.timer.isResting ? Color.wSun : Color.wSea)
                        .frame(width: 8, height: 8)
                    Text(entry.timer.isResting ? KeelMiraWidgetCopy.resting : KeelMiraWidgetCopy.sailing)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                }
                .foregroundStyle(Color.wSand.opacity(0.75))

                Text(entry.timer.itemName.isEmpty ? KeelMiraWidgetCopy.working : entry.timer.itemName)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .padding(.top, 8)

                timerText(fontSize: 36)
                    .padding(.top, 1)

                Text(KeelMiraWidgetCopy.quietTime)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.wSand.opacity(0.64))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                Button(intent: ToggleKeelMiraBreakIntent()) {
                    Label(
                        entry.timer.isResting ? KeelMiraWidgetCopy.resume : KeelMiraWidgetCopy.breakLabel,
                        systemImage: entry.timer.isResting ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Button(intent: MakeKeelMiraLandfallIntent()) {
                    Label(KeelMiraWidgetCopy.landfall, systemImage: "flag.checkered")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .tint(Color.wSand)
            .buttonStyle(WidgetActionButtonStyle())
            .frame(width: 94)
        }
    }

    private var idleMedium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "KeelMira")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.wSand.opacity(0.72))
                Spacer(minLength: 4)
                Text(KeelMiraWidgetCopy.setSailFromWidget)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(KeelMiraWidgetCopy.todayCount(entry.todayMinutes))
                        .font(.system(size: 12, weight: .semibold))
                    Text(KeelMiraWidgetCopy.minuteUnit)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color.wSand.opacity(0.68))
                .padding(.top, 7)
            }
            .frame(width: 118, alignment: .leading)

            if entry.items.isEmpty {
                Text(KeelMiraWidgetCopy.addItemLong)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.wSand.opacity(0.72))
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)],
                    spacing: 7
                ) {
                    ForEach(entry.items.prefix(4)) { item in
                        Button(intent: StartKeelMiraVoyageIntent(item: item)) {
                            HStack(spacing: 6) {
                                WidgetItemSymbol(token: item.symbolToken)
                                    .frame(width: 16, height: 16)
                                Text(item.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9)
                            .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .tint(Color.wSand)
                        .buttonStyle(WidgetActionButtonStyle(accent: WidgetItemColor.color(item.styleToken)))
                        .accessibilityLabel(KeelMiraWidgetCopy.setSail(with: item.name))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func timerText(fontSize: CGFloat) -> some View {
        if entry.timer.isResting {
            Text(WidgetClock.text(entry.timer.elapsedSeconds(at: entry.date)))
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .monospacedDigit()
        } else {
            Text(entry.timer.displayAnchor(at: entry.date), style: .timer)
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    private var preferredItem: KeelMiraWidgetItem? {
        let last = KeelMiraWidgetStore.defaults.string(forKey: KeelMiraWidgetStore.Key.lastItemID)
        return entry.items.first(where: { $0.id == last }) ?? entry.items.first
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.timer.isActive {
                VStack(spacing: 0) {
                    Image(systemName: entry.timer.isResting ? "pause.circle.fill" : "sailboat.fill")
                        .font(.system(size: 12, weight: .medium))
                    Text(WidgetClock.compact(entry.timer.elapsedSeconds(at: entry.date)))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            } else {
                VStack(spacing: 0) {
                    Image(systemName: "sailboat.fill")
                    Text(KeelMiraWidgetCopy.minutes(entry.todayMinutes))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            if entry.timer.isActive {
                Text(entry.timer.isResting ? KeelMiraWidgetCopy.resting : KeelMiraWidgetCopy.sailing)
                    .font(.system(size: 11, weight: .semibold))
                    .widgetAccentable()
                Text(entry.timer.itemName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(WidgetClock.text(entry.timer.elapsedSeconds(at: entry.date)))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text(KeelMiraWidgetCopy.todaysVoyage)
                    .font(.system(size: 11, weight: .semibold))
                    .widgetAccentable()
                Text(KeelMiraWidgetCopy.minutes(entry.todayMinutes))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(KeelMiraWidgetCopy.readyToSail)
                    .font(.system(size: 10, weight: .regular))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        if entry.timer.isActive {
            Label(
                "\(entry.timer.itemName)・\(WidgetClock.text(entry.timer.elapsedSeconds(at: entry.date)))",
                systemImage: entry.timer.isResting ? "pause.circle.fill" : "sailboat.fill"
            )
        } else {
            Label(KeelMiraWidgetCopy.todayMinutes(entry.todayMinutes), systemImage: "sailboat")
        }
    }
}

// MARK: - Background and components

private struct WidgetVoyageStill: View {
    let renderingMode: WidgetRenderingMode

    var body: some View {
        ZStack {
            if renderingMode == .fullColor, let image = voyageImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                WidgetFallbackSea()
            }

            LinearGradient(
                colors: [
                    Color.wNight.opacity(0.12),
                    Color.wNight.opacity(0.34),
                    Color.black.opacity(0.66),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var voyageImage: UIImage? {
        guard let url = KeelMiraWidgetStore.voyageImageURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct WidgetFallbackSea: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [.wNight, Color(h: 0x1E5348)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle()
                    .fill(Color.wSand.opacity(0.78))
                    .frame(width: 34, height: 34)
                    .position(x: geometry.size.width * 0.76, y: geometry.size.height * 0.22)
                Image(systemName: "sailboat.fill")
                    .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.28))
                    .foregroundStyle(Color.wSand.opacity(0.56))
                    .position(x: geometry.size.width * 0.67, y: geometry.size.height * 0.63)
            }
        }
    }
}

private struct WidgetActionButtonStyle: ButtonStyle {
    var accent: Color = Color.white.opacity(0.11)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.wSand.opacity(0.18), lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

private struct WidgetItemSymbol: View {
    let token: String

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
    }

    private var systemName: String {
        switch token {
        case "anchor": "anchor"
        case "wheel": "steeringwheel"
        case "lighthouse": "light.beacon.max.fill"
        case "island": "mountain.2.fill"
        case "phoenix": "bird.fill"
        case "book": "book.closed.fill"
        case "pen": "pencil.line"
        case "sailboat": "sailboat.fill"
        case "attire": "flag.fill"
        default: "location.north.fill"
        }
    }
}

private enum WidgetItemColor {
    static func color(_ token: String) -> Color {
        switch token {
        case "coral": Color.wCoral.opacity(0.32)
        case "seaGreen": Color.wSea.opacity(0.27)
        case "sunYellow": Color.wSun.opacity(0.28)
        case "violet": Color(h: 0x7067A8).opacity(0.32)
        default: Color.white.opacity(0.11)
        }
    }
}

private enum WidgetClock {
    static func text(_ seconds: Int) -> String {
        let value = max(0, seconds)
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let remainder = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }

    static func compact(_ seconds: Int) -> String {
        let value = max(0, seconds)
        if value >= 3_600 { return String(format: "%d:%02d", value / 3_600, (value / 60) % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

// MARK: - Configuration

struct LandfallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: KeelMiraWidgetStore.widgetKind, provider: Provider()) { entry in
            LandfallWidgetView(entry: entry)
        }
        .configurationDisplayName(KeelMiraWidgetCopy.configurationName)
        .description(KeelMiraWidgetCopy.configurationDescription)
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

@main
struct LandfallWidgetBundle: WidgetBundle {
    var body: some Widget { LandfallWidget() }
}
