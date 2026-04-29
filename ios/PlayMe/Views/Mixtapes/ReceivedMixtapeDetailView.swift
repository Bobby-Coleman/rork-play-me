import SwiftUI

/// Read-only mirror of `MixtapeDetailView` for a received mixtape
/// share. Renders the snapshot exactly as the sender authored it
/// (name, description, songs) — no rename, delete, or share-onward
/// affordances. The sender's name is surfaced in the header so the
/// recipient knows who curated the mixtape, and tapping any song
/// opens the same `SongFullScreenFeedView` the rest of the app uses.
struct ReceivedMixtapeDetailView: View {
    let share: MixtapeShare
    let appState: AppState

    @Environment(\.dismiss) private var dismiss
    @State private var fullscreenSeed: FullscreenSeed?
    @State private var descriptionExpanded: Bool = false
    @State private var saveSong: Song?

    private let horizontalPadding: CGFloat = 12
    private let spacing: CGFloat = 10

    private var mixtape: Mixtape { share.mixtape }

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

                            if mixtape.songs.isEmpty {
                                emptyState.padding(.top, 60)
                            } else {
                                PinterestSquareGrid(
                                    items: mixtape.songs,
                                    cellSize: cellSize,
                                    spacing: spacing
                                ) { song, side in
                                    AlbumArtSquare(
                                        url: song.albumArtURL,
                                        cornerRadius: 14,
                                        showsPlaceholderProgress: false,
                                        showsShadow: false,
                                        targetDecodeSide: side
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let idx = mixtape.songs.firstIndex(where: { $0.id == song.id }) {
                                            AudioPlayerService.shared.play(song: song)
                                            fullscreenSeed = FullscreenSeed(
                                                songs: mixtape.songs,
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
            .navigationTitle(mixtape.name)
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
                MixtapeCoverView(mixtape: mixtape, cornerRadius: 12, showsShadow: false)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mixtape.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text("\(mixtape.songCount) song\(mixtape.songCount == 1 ? "" : "s") · from @\(share.sender.username.isEmpty ? share.sender.firstName : share.sender.username)")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
            }

            if let blurb = mixtape.description, !blurb.isEmpty {
                descriptionBlock(blurb)
            }

            // Sender's optional message, if any. Visually distinct from
            // the mixtape's own description so the recipient can tell
            // "what the curator wrote on the cover" apart from "what
            // the friend said when sharing".
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

    private func descriptionBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(descriptionExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if text.count > 120 {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        descriptionExpanded.toggle()
                    }
                } label: {
                    Text(descriptionExpanded ? "less" : "more")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.15))
            Text("This mixtape was empty when shared.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }
}
