import SwiftUI

/// Pinterest-style picker presented from any "Save" entry point. Lists
/// the user's mixtapes (with cover thumbnail, name, song count, and a
/// checkmark when the song lives in the mixtape) and includes a "Create
/// new mixtape" row at the top. Tapping a mixtape toggles membership via
/// `MixtapeStore.toggleSong`.
///
/// The synthetic Liked mixtape is rendered as a read-only row — toggling
/// Liked is intentionally tied to the per-share Like button (heart on art)
/// so the Save sheet never silently mutates someone's likes from a
/// song-only context.
struct SaveToMixtapeSheet: View {
    let song: Song
    let appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var showCreate: Bool = false

    private var store: MixtapeStore { appState.mixtapeStore }
    private var saveService: SaveService { appState.saveService }

    /// User-owned mixtapes only. The synthetic Liked mixtape gets its own
    /// row appended at the bottom so layout stays predictable when the
    /// user has zero user-owned mixtapes.
    private var userMixtapes: [Mixtape] { store.userMixtapes }
    private var likedMixtape: Mixtape {
        store.allMixtapes.first(where: { $0.isSystemLiked })
            ?? Mixtape(id: Mixtape.systemLikedId, ownerId: "", name: "Liked", songs: [], isSystemLiked: true)
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
                            mixtapeRow(for: mixtape, isReadOnly: false)
                                .padding(.horizontal, 16)
                        }

                        mixtapeRow(for: likedMixtape, isReadOnly: true)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)

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
                }
            }
            .navigationTitle("Save to mixtape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(.black)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCreate) {
            CreateMixtapeView(seedSong: song, appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            AlbumArtSquare(url: song.albumArtURL, cornerRadius: 10, showsShadow: false)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist)
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
    }

    private func mixtapeRow(for mixtape: Mixtape, isReadOnly: Bool) -> some View {
        let isMember = mixtape.isSystemLiked
            ? appState.likedShares.contains(where: { $0.song.id == song.id })
            : (mixtape.songs.contains(where: { $0.id == song.id })
                || saveService.mixtapeIds(forSongId: song.id).contains(mixtape.id))

        return Button {
            guard !isReadOnly else { return }
            Task { await store.toggleSong(song, in: mixtape.id) }
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

                if isReadOnly {
                    Text("Like the song")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isMember ? .white : .white.opacity(0.3))
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .opacity(isReadOnly ? 0.7 : 1.0)
    }

    private func songCountLabel(for mixtape: Mixtape) -> String {
        let count = mixtape.songCount
        return count == 1 ? "1 song" : "\(count) songs"
    }

    private var emptyHint: some View {
        Text("You don't have any mixtapes yet. Create one to start saving.")
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.45))
            .multilineTextAlignment(.center)
    }
}
