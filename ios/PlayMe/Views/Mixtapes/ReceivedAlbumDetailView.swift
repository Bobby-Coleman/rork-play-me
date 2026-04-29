import SwiftUI

/// Read-only detail view for a received album share. Shows the album
/// artwork + sender attribution, then a Pinterest-style grid of the
/// snapshot's tracks. Tapping any song opens the same fullscreen feed
/// the rest of the app uses; long-pressing offers "Save to mixtape"
/// for the individual track.
struct ReceivedAlbumDetailView: View {
    let share: AlbumShare
    let appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var fullscreenSeed: FullscreenSeed?
    @State private var saveSong: Song?

    private let horizontalPadding: CGFloat = 12
    private let spacing: CGFloat = 10

    private var album: Album { share.album }
    private var songs: [Song] { share.songs }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let cellSize = PinterestGridLayout.cellSize(
                    containerWidth: geo.size.width,
                    horizontalPadding: horizontalPadding,
                    spacing: spacing
                )
                ZStack {
                    Color.black.ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 0) {
                            header
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .padding(.bottom, 18)

                            if songs.isEmpty {
                                emptyState.padding(.top, 60)
                            } else {
                                PinterestSquareGrid(
                                    items: songs,
                                    cellSize: cellSize,
                                    spacing: spacing
                                ) { song, side in
                                    AlbumArtSquare(
                                        url: song.albumArtURL.isEmpty ? album.artworkURL : song.albumArtURL,
                                        cornerRadius: 14,
                                        showsPlaceholderProgress: false,
                                        showsShadow: false,
                                        targetDecodeSide: side
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let idx = songs.firstIndex(where: { $0.id == song.id }) {
                                            AudioPlayerService.shared.play(song: song)
                                            fullscreenSeed = FullscreenSeed(
                                                songs: songs,
                                                startIndex: idx
                                            )
                                        }
                                    }
                                    .contextMenu {
                                        Button {
                                            saveSong = song
                                        } label: {
                                            Label("Save to mixtape", systemImage: "plus.square.on.square")
                                        }
                                    }
                                }
                                .padding(.horizontal, horizontalPadding)
                                .padding(.bottom, 32)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle(album.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $fullscreenSeed) { seed in
            SongFullScreenFeedView(
                songs: seed.songs,
                startIndex: seed.startIndex,
                appState: appState
            )
        }
        .sheet(item: $saveSong) { song in
            SaveToMixtapeSheet(song: song, appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08))
                    AsyncImage(url: URL(string: album.artworkURL)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 12))
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 3) {
                    Text(album.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let artist = album.artistName, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Text("Album · from @\(share.sender.username.isEmpty ? share.sender.firstName : share.sender.username)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer()
            }

            if let note = share.note, !note.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 1)
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))
            Text("This album shipped without any tracks.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }
}
