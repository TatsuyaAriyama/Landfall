import SwiftUI

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var messageFocused: Bool

    @State private var category: FeedbackCategory = .idea
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var submittedFeedbackID: String?
    @State private var errorMessage: String?

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !isSubmitting && trimmedMessage.count >= FeedbackService.minimumLength
    }

    private var remainingCharactersToSubmit: Int {
        max(0, FeedbackService.minimumLength - trimmedMessage.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            LFBackHeader(title: "Send feedback") { dismiss() }
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.vertical, 6)

            Rectangle()
                .fill(LFColor.ink.opacity(0.08))
                .frame(height: 1)

            if submittedFeedbackID != nil {
                successView
            } else {
                formView
            }
        }
        .background(LFColor.paper.ignoresSafeArea())
        .interactiveDismissDisabled(isSubmitting)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { messageFocused = false }
            }
        }
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Help shape the next voyage")
                        .font(LFFont.copy(24))
                        .foregroundStyle(LFColor.ink)
                    Text("Tell the crew what would make KeelMira better. Every note reaches the operations team.")
                        .font(LFFont.label(14))
                        .foregroundStyle(LFColor.ink.opacity(0.60))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Category")

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 9),
                            GridItem(.flexible(), spacing: 9),
                        ],
                        spacing: 9
                    ) {
                        ForEach(FeedbackCategory.allCases) { option in
                            categoryButton(option)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        sectionLabel("Your suggestion")
                        Spacer()
                        Text("\(message.count) / \(FeedbackService.maximumLength)")
                            .font(LFFont.label(12))
                            .foregroundStyle(LFColor.ink.opacity(0.42))
                            .monospacedDigit()
                    }

                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("What should we improve? Please include what you expected and what happened.")
                                .font(LFFont.label(15))
                                .foregroundStyle(LFColor.ink.opacity(0.36))
                                .padding(.horizontal, 17)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $message)
                            .font(LFFont.copy(16))
                            .foregroundStyle(LFColor.ink)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .frame(minHeight: 190)
                            .focused($messageFocused)
                            .onChange(of: message) { _, newValue in
                                if newValue.count > FeedbackService.maximumLength {
                                    message = String(newValue.prefix(FeedbackService.maximumLength))
                                }
                                errorMessage = nil
                            }
                    }
                    .background(LFColor.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(messageFocused ? LFColor.returnOrange.opacity(0.65) : LFColor.ink.opacity(0.10), lineWidth: 1)
                    }

                    Text("App version, iOS version, and language are included automatically. Study records are never attached.")
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.ink.opacity(0.48))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(LFFont.label(13))
                        .foregroundStyle(LFColor.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if remainingCharactersToSubmit > 0 {
                    Label(
                        LF.format(
                            "%lld more characters to send",
                            Int64(remainingCharactersToSubmit)
                        ),
                        systemImage: "character.cursor.ibeam"
                    )
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.returnOrange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isStaticText)
                }

                Button {
                    submit()
                } label: {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView()
                                .tint(LFColor.paper)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isSubmitting ? "Sending…" : "Send to the crew")
                    }
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(canSubmit ? LFColor.harborTeal : LFColor.ink.opacity(0.20), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .accessibilityHint(Text("Sends this suggestion privately to the operations team."))
            }
            .padding(LFMetrics.cardPadding)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var successView: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 58, weight: .regular))
                .foregroundStyle(LFColor.harborTeal)
                .symbolEffect(.bounce, value: submittedFeedbackID)

            VStack(spacing: 7) {
                Text("Feedback received")
                    .font(LFFont.copy(25))
                    .foregroundStyle(LFColor.ink)
                Text("Thank you. The operations crew can now review your note.")
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink.opacity(0.58))
                    .multilineTextAlignment(.center)
            }

            Button("Close") { dismiss() }
                .font(LFFont.copy(17))
                .foregroundStyle(LFColor.paper)
                .frame(maxWidth: 260)
                .frame(height: 52)
                .background(LFColor.harborTeal, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .buttonStyle(.plain)

            Spacer()
            Spacer()
        }
        .padding(LFMetrics.cardPadding)
    }

    private func categoryButton(_ option: FeedbackCategory) -> some View {
        let selected = category == option
        return Button {
            category = option
            Haptics.tap(.light)
        } label: {
            Label(option.title, systemImage: option.symbol)
                .font(LFFont.label(14))
                .foregroundStyle(selected ? LFColor.paper : LFColor.ink.opacity(0.72))
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(selected ? LFColor.harborTeal : LFColor.ink.opacity(0.055), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(LFFont.label(13))
            .tracking(1.4)
            .foregroundStyle(LFColor.ink.opacity(0.52))
    }

    private func submit() {
        guard canSubmit else { return }
        messageFocused = false
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                submittedFeedbackID = try await FeedbackService.submit(
                    category: category,
                    message: trimmedMessage
                )
                Haptics.success()
            } catch {
                if let feedbackError = error as? FeedbackSubmissionError {
                    errorMessage = feedbackError.localizedDescription
                } else {
                    errorMessage = String(localized: "Your feedback could not be sent. Check your connection and try again.")
                }
                Haptics.error()
            }
            isSubmitting = false
        }
    }
}
