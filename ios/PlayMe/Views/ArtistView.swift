import SwiftUI

/// Minimalist Spotify-style artist page. Shows popular tracks + a grid of
/// albums. Type-only header (iTunes doesn't expose artist images and we're
/// deliberately staying off any paid auth flow).
struct ArtistView: View {
    let artistId: String
    /// Optional hint so the header has something to show while the network
    /// request resolves. Falls back to the fetched value once loaded.
    var initialArtistName: String? = nil
    let appState: AppState

    @Environment(\.dismiss) private var dismiss

    @State private var details: ArtistDetails?
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var detailSong: Song?
    @State private var detailAlbum: Album?

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if isLoading && details == nil {
                            skeleton
                        } else if let msg = errorMessage, details == nil {
                            errorView(msg)
                        } else if let details {
                            content(details)
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
        .task(id: artistId) {
            await load()
        }
        .sheet(item: $detailSong) { song in
            SongDetailSheet(song: song, appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $detailAlbum) { album in
            AlbumDetailView(album: album, appState: appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ARTIST")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
            Text(details?.artistName.isEmpty == false ? details!.artistName : (initialArtistName ?? ""))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func content(_ details: ArtistDetails) -> some View {
        if !details.topTracks.isEmpty {
            sectionHeader("Popular")
            VStack(spacing: 0) {
                ForEach(Array(details.topTracks.prefix(10).enumerated()), id: \.offset) { pair in
                    let song = pair.element
                    popularRow(index: pair.offset + 1, song: song)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }

        if !details.albums.isEmpty {
            sectionHeader("Albums")
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(details.albums) { album in
                    albumTile(album)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
    }

    private func popularRow(index: Int, song: Song) -> some View {
        Button {
            detailSong = song
        } label: {
            HStack(spacing: 14) {
                Text("\(index)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 22, alignment: .leading)

                AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color(.systemGray5)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 4))

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
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func albumTile(_ album: Album) -> some View {
        Button {
            detailAlbum = album
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: URL(string: album.artworkURL)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color(.systemGray5)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let year = album.releaseYear {
                        Text(year)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Skeleton / error

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 10) {
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 24)

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(0..<4) { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, 24)
        }
        .redacted(reason: .placeholder)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.3))
            Text("We couldn't pull this artist's catalog")
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

    // MARK: - Load

    private func load(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await ArtistLookupService.shared.fetchArtistDetails(
                artistId: artistId,
                forceRefresh: forceRefresh
            )
            details = fetched
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
