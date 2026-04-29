import SwiftUI

/// Album-flavored variant of `SaveToMixtapeSheet`. Lists the user's
/// mixtapes; tapping one shows a confirmation alert ("this will add N
/// songs to '<mixtape>'") and on confirm fetches the album's tracklist
/// and adds each song individually via `AppState.addAlbumToMixtape`.
///
/// The synthetic Liked mixtape is excluded — Liked is per-song share
/// based, so bulk-album saves don't fit its model.
struct SaveAlbumToMixtapeSheet: View {
    let album: Album
    let appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var showCreate: Bool = false
    @State private var pendingMixtape: Mixtape?
    /// Surfaces a "Adding…" overlay while the tracklist fetch + N adds
    /// run, so the user understands the sheet hasn't frozen on a slow
    /// network.
    @State private var isAdding: Bool = false
    /// Album track count surfaced in the confirmation alert. Loaded
    /// lazily once the sheet appears so the alert can read "Add N
    /// songs?" rather than the more anxious "Add this album?". Falls
    /// back to `album.trackCount` when iTunes' lookup hasn't returned
    /// yet.
    @State private var resolvedTrackCount: Int?

    private var store: MixtapeStore { appState.mixtapeStore }

    /// User-owned mixtapes only (excluding the synthetic Liked one).
    private var userMixtapes: [Mixtape] { store.userMixtapes }

    /// What the alert prefers to display: live-looked-up count, then
    /// the catalog `trackCount`, then a generic plural.
    private var trackCountDisplay: String {
        if let n = resolvedTrackCount { return "\(n) song\(n == 1 ? "" : "s")" }
        if let n = album.trackCount { return "\(n) song\(n == 1 ? "" : "s")" }
        return "every song"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 20)

                        createRow
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)

                        ForEach(userMixtapes) { mixtape in
                            mixtapeRow(for: mixtape)
                                .padding(.horizontal, 16)
                        }

                        if userMixtapes.isEmpty && !store.hasLoaded {
                            ProgressView()
                                .tint(.white)
                                .padding(.vertical, 24)
                        } else if userMixtapes.isEmpty {
                            emptyHint
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)

                if isAdding {
                    addingOverlay
                }
            }
            .navigationTitle("Save album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                        .disabled(isAdding)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCreate) {
            // Same cover-required create flow as song saves; empty
            // mixtape lands at the top of `userMixtapes` for the user
            // to tap and commit the album.
            CreateMixtapeView(seedSong: nil, appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "Add full album?",
            isPresented: Binding(
                get: { pendingMixtape != nil && !isAdding },
                set: { if !$0 { pendingMixtape = nil } }
            ),
            presenting: pendingMixtape
        ) { mix in
            Button("Add \(trackCountDisplay)") {
                commit(to: mix)
            }
            Button("Cancel", role: .cancel) {
                pendingMixtape = nil
            }
        } message: { mix in
            Text("\"\(album.name)\" will be added to \"\(mix.name)\" as \(trackCountDisplay).")
        }
        .task(id: album.id) {
            // Pre-fetch the tracklist (cached after the first call) so
            // the confirmation alert can show an accurate count even
            // when the catalog `trackCount` was nil in the search row.
            // Errors are swallowed — the alert still works with the
            // catalog count or the generic fallback.
            if let count = try? await ArtistLookupService.shared
                .fetchAlbumTracks(albumId: album.id).count {
                resolvedTrackCount = count
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                AsyncImage(url: URL(string: album.artworkURL)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text((album.artistName ?? "Album") + " · " + trackCountDisplay)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Rows

    private var createRow: some View {
        Button {
            showCreate = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)

                Text("Create new mixtape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(isAdding)
    }

    private func mixtapeRow(for mixtape: Mixtape) -> some View {
        Button {
            pendingMixtape = mixtape
        } label: {
            HStack(spacing: 12) {
                MixtapeCoverView(mixtape: mixtape, cornerRadius: 12, showsShadow: false)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mixtape.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(songCountLabel(for: mixtape))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(isAdding)
    }

    private func songCountLabel(for mixtape: Mixtape) -> String {
        let count = mixtape.songCount
        return count == 1 ? "1 song" : "\(count) songs"
    }

    private var emptyHint: some View {
        Text("You don't have any mixtapes yet. Create one to save this album.")
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.45))
            .multilineTextAlignment(.center)
    }

    // MARK: - Adding overlay

    private var addingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
                Text("Adding songs…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .transition(.opacity)
    }

    // MARK: - Commit

    private func commit(to mixtape: Mixtape) {
        pendingMixtape = nil
        isAdding = true
        Task {
            _ = await appState.addAlbumToMixtape(album, mixtapeId: mixtape.id)
            isAdding = false
            dismiss()
        }
    }
}

