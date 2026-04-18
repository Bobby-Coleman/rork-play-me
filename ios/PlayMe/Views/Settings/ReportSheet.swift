import SwiftUI

enum ReportTarget: Identifiable {
    case user(AppUser)
    case share(SongShare)
    case message(senderUid: String, senderName: String, conversationId: String, messageId: String)

    var id: String {
        switch self {
        case .user(let u): return "user:\(u.id)"
        case .share(let s): return "share:\(s.id)"
        case .message(_, _, let c, let m): return "message:\(c)/\(m)"
        }
    }

    var targetName: String {
        switch self {
        case .user(let u): return u.firstName.isEmpty ? "this user" : u.firstName
        case .share(let s): return s.sender.firstName.isEmpty ? "this song" : "\(s.sender.firstName)\u{2019}s song"
        case .message(_, let name, _, _): return name.isEmpty ? "this message" : "\(name)\u{2019}s message"
        }
    }
}

private let reportReasons: [String] = [
    "Spam",
    "Harassment or bullying",
    "Hate speech or symbols",
    "Sexual or inappropriate content",
    "Violence or self-harm",
    "Impersonation",
    "Other",
]

/// Bottom-sheet report flow used from friend rows, song cards, and message
/// context menus. Writes to `reports/*` via AppState; the sheet closes on
/// success and the caller can show a toast.
struct ReportSheet: View {
    let target: ReportTarget
    let appState: AppState
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: String = reportReasons[0]
    @State private var note: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Report \(target.targetName)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Your report is anonymous. Our team reviews reports within 24 hours.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(reportReasons, id: \.self) { reason in
                            Button {
                                selectedReason = reason
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedReason == reason ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(selectedReason == reason ? Color(red: 0.76, green: 0.38, blue: 0.35) : .white.opacity(0.3))
                                    Text(reason)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.white)
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            if reason != reportReasons.last {
                                Divider().background(Color.white.opacity(0.06))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Color.white.opacity(0.04))
                    .clipShape(.rect(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add details (optional)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        TextField("", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(.rect(cornerRadius: 10))
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text(isSubmitting ? "Sending..." : "Submit report")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.76, green: 0.38, blue: 0.35))
                        .clipShape(.rect(cornerRadius: 12))
                    }
                    .disabled(isSubmitting)
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationBackground(.black)
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let success: Bool

        switch target {
        case .user(let u):
            success = await appState.reportUser(u.id, reason: selectedReason, note: trimmedNote.isEmpty ? nil : trimmedNote)
        case .share(let s):
            success = await appState.reportShare(s, reason: selectedReason, note: trimmedNote.isEmpty ? nil : trimmedNote)
        case .message(let senderUid, _, let conv, let msg):
            success = await appState.reportMessage(senderUid: senderUid, conversationId: conv, messageId: msg, reason: selectedReason, note: trimmedNote.isEmpty ? nil : trimmedNote)
        }

        isSubmitting = false
        if success {
            onSubmitted()
            dismiss()
        } else {
            errorMessage = "Couldn't send report. Check your connection and try again."
        }
    }
}
