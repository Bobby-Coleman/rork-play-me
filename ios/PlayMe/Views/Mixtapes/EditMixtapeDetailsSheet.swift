import SwiftUI

/// Edit-details sheet for a user-owned mixtape. Mirrors Spotify's
/// "Edit playlist details" pattern: one bottom sheet with both the
/// name and an optional "what's this mixtape about" description, and
/// a single Save action that writes both. Replaces the older
/// rename-only alert so users can author a description without a
/// second flow.
///
/// `MixtapeStore` enforces both the trim/empty rules and the
/// "system Liked can't edit" guard, so this sheet trusts the caller
/// to only present it for editable mixtapes.
struct EditMixtapeDetailsSheet: View {
    let mixtape: Mixtape
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var details: String = ""
    @FocusState private var nameFocused: Bool

    /// Hard cap on the description so we never have to truncate at
    /// render time. 300 is roughly what Spotify allows on playlists.
    private let descriptionLimit = 300

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        nameField
                        descriptionField
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commit() }
                        .foregroundStyle(canSave ? .white : .white.opacity(0.3))
                        .disabled(!canSave)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.black)
        .onAppear {
            name = mixtape.name
            details = mixtape.description ?? ""
            // Focus the name field immediately — that's the most
            // commonly edited piece, and skipping a tap to dismiss the
            // keyboard onto the description is a small win.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                nameFocused = true
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            TextField(
                "",
                text: $name,
                prompt: Text("Mixtape name").foregroundColor(.white.opacity(0.35))
            )
            .focused($nameFocused)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .tint(.white)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08))
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(details.count)/\(descriptionLimit)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(details.count >= descriptionLimit ? 0.7 : 0.3))
            }
            TextField(
                "",
                text: $details,
                prompt: Text("What's this mixtape about?").foregroundColor(.white.opacity(0.35)),
                axis: .vertical
            )
            .lineLimit(3...8)
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08))
            .clipShape(.rect(cornerRadius: 10))
            .onChange(of: details) { _, newValue in
                if newValue.count > descriptionLimit {
                    details = String(newValue.prefix(descriptionLimit))
                }
            }
        }
    }

    private func commit() {
        guard canSave else { return }
        let store = appState.mixtapeStore
        let id = mixtape.id
        let nextName = name
        let nextDescription = details
        Task {
            // Issue both writes in parallel — independent fields, both
            // cheap, and both update the local store optimistically so
            // there is no flicker while the second one settles.
            async let a: Void = store.rename(mixtapeId: id, to: nextName)
            async let b: Void = store.updateDescription(mixtapeId: id, to: nextDescription)
            _ = await (a, b)
        }
        dismiss()
    }
}
