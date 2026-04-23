import SwiftUI

/// Simple track list for an album. Tapping a row routes into
/// `SongDetailSheet` — same unified hub every other song surface uses.
struct AlbumDetailView: View {
    let album: Album
    let appState: AppState

    @Environment(\.dismiss) private var dismiss

    @State private var tracks: [Song] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var detailSong: Song?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        artworkHeader
                        if isLoading && tracks.isEmpty {
                            skeleton
                        } else if let msg = errorMessage, tracks.isEmpty {
                            errorView(msg)
                        } else {
                            trackList
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(.black)
        .task(id: album.id) {
            await load()
        }
        .sheet(item: $detailSong) { song in
            SongDetailSheet(song: song, appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var artworkHeader: some View {
        VStack(spacing: 16) {
            AsyncImage(url: URL(string: album.artworkURL)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(width: 200, height: 200)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

            VStack(spacing: 6) {
                Text(album.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if let year = album.releaseYear {
                    Text(year)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { pair in
                trackRow(index: pair.offset + 1, song: pair.element)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }

    private func trackRow(index: Int, song: Song) -> some View {
        Button {
            detailSong = song
        } label: {
            HStack(spacing: 14) {
                Text("\(index)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 22, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                Text(song.duration)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Color.white.opacity(0.05).frame(height: 0.5)
        }
    }

    private var skeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<6) { _ in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 40)
            }
        }
        .padding(.horizontal, 24)
        .redacted(reason: .placeholder)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.3))
            Text("We couldn't load this album")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await load(forceRefresh: true) }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1))
            .clipShape(.capsule)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func load(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await ArtistLookupService.shared.fetchAlbumTracks(
                albumId: album.id,
                forceRefresh: forceRefresh
            )
            tracks = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
