import SwiftUI
import SwiftData

/// 項目のページ。累計・記録一覧を見返し、ここから刻む。
/// 「記録したものが残らない/読み返せない」を解くための中心画面。
struct ItemDetailView: View {
    let item: StudyItem

    @Environment(\.dismiss) private var dismiss
    @State private var recording = false
    @State private var editing = false
    @State private var showWelcomeBack = false

    /// 新しい順のセッション。
    private var sessions: [StudySession] {
        item.sessions.sorted { $0.date > $1.date }
    }

    private var totalMinutes: Int {
        item.sessions.reduce(0) { $0 + $1.minutes }
    }

    private var recordedDays: Int {
        let calendar = Calendar.current
        return Set(item.sessions.map { calendar.startOfDay(for: $0.date) }).count
    }

    var body: some View {
        ZStack {
            LFColor.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    statStrip
                        .padding(.top, 28)
                    recordButton
                        .padding(.top, 24)
                    logSection
                        .padding(.top, 36)
                }
                .padding(LFMetrics.cardPadding)
            }

            if showWelcomeBack {
                welcomeBackOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Home")
                    }
                    .font(LFFont.label(16))
                    .foregroundStyle(LFColor.ink)
                }
            }
        }
        .toolbarBackground(LFColor.paper, for: .navigationBar)
        .sheet(isPresented: $recording) {
            RecordSessionSheet(
                item: item,
                onSaved: handleSaved,
                onEdit: { _ in editing = true }
            )
        }
        .sheet(isPresented: $editing) {
            ItemEditorSheet(existing: item, onDeleted: { dismiss() })
        }
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(spacing: 16) {
            ItemTileArt(item: item)
                .frame(width: 72, height: 72)
            Text(item.name)
                .font(LFFont.copy(24))
                .foregroundStyle(LFColor.ink)
                .lineLimit(2)
            Spacer()
        }
    }

    // MARK: - 統計(累計/記録日数/回数)

    private var statStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            // 累計は整形済みの期間文字列(LFがロケール追従)。日数・回数は Text で言語追従。
            statBlock(label: "Total", value: Text(verbatim: LF.duration(minutes: totalMinutes)), alignment: .leading)
            statBlock(label: "Days", value: Text("\(recordedDays) days"), alignment: .center)
            statBlock(label: "Sessions", value: Text("\(item.sessions.count) sessions"), alignment: .trailing)
        }
    }

    private func statBlock(label: LocalizedStringKey, value: Text, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(label)
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.5))
            value
                .font(LFFont.number(26))
                .foregroundStyle(LFColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
    }

    private var recordButton: some View {
        Button {
            recording = true
        } label: {
            Text("Log")
                .font(LFFont.copy(18))
                .foregroundStyle(LFColor.paper)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(LFColor.ink)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 記録の一覧

    @ViewBuilder
    private var logSection: some View {
        Text("History")
            .font(LFFont.label(13))
            .tracking(1)
            .foregroundStyle(LFColor.ink.opacity(0.5))

        if sessions.isEmpty {
            Text("Nothing logged yet. Make your first mark.")
                .font(LFFont.copy(16))
                .foregroundStyle(LFColor.ink.opacity(0.5))
                .padding(.top, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.persistentModelID) { index, session in
                    if index > 0 {
                        Rectangle()
                            .fill(LFColor.ink.opacity(0.08))
                            .frame(height: 1)
                    }
                    logRow(session)
                }
            }
            .padding(.top, 12)
        }
    }

    private func logRow(_ session: StudySession) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LF.dayMonth(session.date))
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink)
                Text(LF.weekdayFull(session.date))
                    .font(LFFont.label(11))
                    .foregroundStyle(LFColor.ink.opacity(0.4))
            }
            .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(LF.duration(minutes: session.minutes))
                    .font(LFFont.copy(17))
                    .monospacedDigit()
                    .foregroundStyle(LFColor.ink)
                if let note = session.note, !note.isEmpty {
                    Text(note)
                        .font(LFFont.label(15))
                        .foregroundStyle(LFColor.ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
    }

    // MARK: - おかえり演出

    private var welcomeBackOverlay: some View {
        ZStack {
            LFColor.paper.opacity(0.94).ignoresSafeArea()
            Text("Welcome back.")
                .font(LFFont.copy(26))
                .foregroundStyle(LFColor.ink)
        }
        .transition(.opacity)
    }

    private func handleSaved(blanks: Int?) {
        guard let blanks, blanks >= 2 else { return }
        Task {
            withAnimation(.easeInOut(duration: 0.25)) { showWelcomeBack = true }
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            withAnimation(.easeInOut(duration: 0.25)) { showWelcomeBack = false }
        }
    }

    // MARK: - 整形

    private func frameAlignment(_ alignment: HorizontalAlignment) -> Alignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }
}
