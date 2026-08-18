import SwiftUI

/// Island select: the screen a player opens to choose which island to sail to.
///
/// Drawn as a save-slot screen, not a settings list, because the second slot is
/// what the Voyage Pass sells: a locked island has to be seen before anyone
/// will pay for it. Nothing here loads a scene — the cards run on the summaries
/// alone, so opening the screen stays instant.
///
/// The palette is deliberately colourless. Hue was carrying the state before,
/// which made the screen loud and left the cards looking invented; now weight
/// and contrast carry it, and the only picture on screen is the app's own mark.
struct HomeIslandSlotsView: View {
    @ObservedObject private var book: HomeIslandSlotBook
    /// The pass decides whether the second island is reachable, so this screen
    /// has to redraw when it changes hands.
    @StateObject private var pass = VoyagePassStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var renamingIndex: Int?
    @State private var draftName = ""

    private let onSelect: (Int) -> Void
    private let onOpenVoyagePass: () -> Void

    init(
        book: HomeIslandSlotBook,
        onSelect: @escaping (Int) -> Void,
        onOpenVoyagePass: @escaping () -> Void
    ) {
        _book = ObservedObject(wrappedValue: book)
        self.onSelect = onSelect
        self.onOpenVoyagePass = onOpenVoyagePass
    }

    var body: some View {
        ZStack {
            backdrop
            content
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // An island edited elsewhere must not show a stale count here.
            book.refresh()
            appeared = true
        }
        .alert("Island name", isPresented: renameBinding) {
            TextField("Island name", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) { renamingIndex = nil }
            Button("Save") {
                if let renamingIndex {
                    book.rename(index: renamingIndex, to: draftName)
                }
                renamingIndex = nil
            }
        }
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [Color(hex: 0x1B1C1E), Color(hex: 0x111213)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var content: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heading
                    cards
                        .padding(.top, 22)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                // Two cards and nothing else: on iPad they sit in the middle of
                // the room rather than clinging to the ceiling.
                .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var heading: some View {
        Text("Islands")
            .font(LFFont.copy(24))
            .foregroundStyle(.white.opacity(0.92))
            .opacity(appeared ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: appeared)
    }

    private var cards: some View {
        VStack(spacing: 12) {
            ForEach(HomeIslandSlotBook.slots) { slot in
                card(for: slot)
            }
        }
    }

    private func card(for slot: HomeIslandSlot) -> some View {
        let state = state(for: slot)
        // The edit control sits beside the card rather than inside it: a button
        // nested in a button's label never gets its own taps.
        return ZStack(alignment: .trailing) {
            Button {
                tap(slot: slot, state: state)
            } label: {
                HomeIslandSlotCard(
                    slot: slot,
                    name: book.name(at: slot.index),
                    summary: book.summary(at: slot.index),
                    state: state
                )
            }
            .buttonStyle(LFPressableButtonStyle(scale: 0.98))
            .accessibilityAddTraits(state == .active ? [.isSelected] : [])
            .accessibilityHint(hint(for: state))

            if state != .locked {
                editButton(for: slot)
                    .padding(.trailing, 44)
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: appeared)
    }

    private func editButton(for slot: HomeIslandSlot) -> some View {
        Button {
            draftName = book.hasCustomName(at: slot.index) ? book.name(at: slot.index) : ""
            renamingIndex = slot.index
            Haptics.tap(.light)
        } label: {
            Text("Edit")
                .font(LFFont.label(10))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text("Island name"))
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingIndex != nil },
            set: { if !$0 { renamingIndex = nil } }
        )
    }

    /// `effectiveIndex` rather than `activeIndex`, so a lapsed pass marks the
    /// first island as the one being sailed instead of the one it can't open.
    private func state(for slot: HomeIslandSlot) -> HomeIslandSlotState {
        guard book.isUnlocked(index: slot.index) else { return .locked }
        if slot.index == book.effectiveIndex { return .active }
        let summary = book.summary(at: slot.index)
        return (summary?.isEmpty ?? true) ? .empty : .ready
    }

    private func tap(slot: HomeIslandSlot, state: HomeIslandSlotState) {
        Haptics.tap(state == .locked ? .light : .medium)
        if state == .locked {
            onOpenVoyagePass()
        } else {
            onSelect(slot.index)
        }
    }

    private func hint(for state: HomeIslandSlotState) -> Text {
        state == .locked ? Text("Opens Voyage Pass") : Text("Sail to this island")
    }
}

/// The four ways a slot can read. Deciding once keeps the card free to draw.
private enum HomeIslandSlotState {
    case active
    case ready
    case empty
    case locked
}

private struct HomeIslandSlotCard: View {
    let slot: HomeIslandSlot
    let name: String
    let summary: HomeIslandSlotSummary?
    let state: HomeIslandSlotState

    private static let markSide: CGFloat = 60

    var body: some View {
        HStack(spacing: 14) {
            mark
            details
            Spacer(minLength: 74)
            accessory
        }
        .padding(14)
        .background { background }
        .contentShape(shape)
    }

    /// The app's own icon, unaltered. A hand-drawn approximation of it read as
    /// a near-miss of the real thing, which is worse than no picture at all.
    private var mark: some View {
        Image("ServiceMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.markSide, height: Self.markSide)
            .clipShape(RoundedRectangle(cornerRadius: Self.markSide * 0.22, style: .continuous))
            .opacity(markOpacity)
            .saturation(state == .active || state == .ready ? 1 : 0.35)
            .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            titleRow
            metrics
        }
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(verbatim: name)
                .font(LFFont.copy(17))
                .foregroundStyle(.white.opacity(titleOpacity))
                .lineLimit(1)
            badge
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .active:
            chip("Sailing", opacity: 0.92, background: 0.16)
        case .locked:
            chip("Voyage Pass", opacity: 0.66, background: 0.10)
        case .ready, .empty:
            EmptyView()
        }
    }

    private func chip(_ title: LocalizedStringKey, opacity: Double, background: Double) -> some View {
        Text(title)
            .font(LFFont.label(10))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(opacity))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(background), in: Capsule())
    }

    /// Figures, not sentences. An untouched slot says only that it is new.
    @ViewBuilder
    private var metrics: some View {
        if let summary, let updatedAt = summary.updatedAt {
            HStack(spacing: 8) {
                Text(verbatim: "\(summary.placementCount)")
                    .font(LFFont.number(15))
                    .foregroundStyle(.white.opacity(state == .active ? 0.82 : 0.62))
                Text("Props")
                    .font(LFFont.label(11))
                    .foregroundStyle(.white.opacity(0.38))
                Text(verbatim: LF.fullDate(updatedAt))
                    .font(LFFont.label(11))
                    .foregroundStyle(.white.opacity(0.30))
            }
        } else {
            Text("New island")
                .font(LFFont.label(12))
                .foregroundStyle(.white.opacity(0.40))
        }
    }

    private var accessory: some View {
        Image(systemName: state == .locked ? "lock.fill" : "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(state == .active ? 0.66 : 0.34))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var background: some View {
        ZStack {
            shape.fill(.white.opacity(fillOpacity))
            shape.strokeBorder(
                .white.opacity(state == .active ? 0.30 : 0.09),
                lineWidth: state == .active ? 1.5 : 1
            )
        }
    }

    private var fillOpacity: Double {
        switch state {
        case .active: return 0.10
        case .ready: return 0.06
        case .empty, .locked: return 0.04
        }
    }

    private var titleOpacity: Double {
        switch state {
        case .active: return 0.95
        case .ready: return 0.86
        case .empty, .locked: return 0.62
        }
    }

    private var markOpacity: Double {
        switch state {
        case .active: return 1
        case .ready: return 0.88
        case .empty: return 0.32
        case .locked: return 0.42
        }
    }
}
