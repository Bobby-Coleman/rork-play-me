import SwiftUI

/// Modal name-entry sheet pushed from `SaveToMixtapeSheet` when the user
/// taps "Create new mixtape". Creates the mixtape via `MixtapeStore.create`
/// and, on success, immediately adds the song that triggered the sheet so
/// the user lands back in `SaveToMixtapeSheet` with the new mixtape
/// already containing the song.
struct CreateMixtapeView: View {
    let song: Song
    let appState: AppState
    /// Callback invoked once the mixtape is created and the song is added,
    /// so the parent sheet can either dismiss itself or refresh state.
    var onCreated: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmed.isEmpty && !isCreating
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    AlbumArtSquare(url: song.albumArtURL, showsShadow: true)
                        .frame(width: 140, height: 140)
                        .padding(.top, 32)

                    VStack(spacing: 6) {
                        Text("New mixtape")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Save \(song.title) to a new collection.")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 24)

                    TextField(
                        "",
                        text: $name,
                        prompt: Text("Mixtape name").foregroundColor(.white.opacity(0.4))
                    )
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await create() } }
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 14))
                    .padding(.horizontal, 24)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(.horizontal, 24)
                    }

                    Spacer()

                    Button {
                        Task { await create() }
                    } label: {
                        HStack {
                            Spacer()
                            if isCreating {
                                ProgressView().tint(.black)
                            } else {
                                Text("Create & Save")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Spacer()
                        }
                        .foregroundStyle(.black)
                        .padding(.vertical, 14)
                        .background(canCreate ? Color.white : Color.white.opacity(0.4))
                        .clipShape(.capsule)
                    }
                    .disabled(!canCreate)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .onAppear { nameFocused = true }
    }

    private func create() async {
        guard canCreate else { return }
        isCreating = true
        errorMessage = nil
        if let mixtape = await appState.mixtapeStore.create(name: trimmed) {
            await appState.mixtapeStore.addSong(song, to: mixtape.id)
            onCreated?()
            dismiss()
        } else {
            errorMessage = "Couldn't create mixtape. Try again."
            isCreating = false
        }
    }
}
