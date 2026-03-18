import SwiftUI

struct SendSongSheet: View {
    @Environment(\.dismiss) private var dismiss
    let appState: AppState

    @State private var searchText: String = ""
    @State private var selectedSong: Song?
    @State private var step: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if step == 0 {
                    songSearchView
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)))
                } else {
                    FriendSelectorView(
                        song: selectedSong!,
                        appState: appState,
                        onBack: { withAnimation(.spring(duration: 0.3)) { step = 0 } },
                        onSent: { dismiss() }
                    )
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
                }
            }
            .animation(.spring(duration: 0.3), value: step)
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
    }

    private var songSearchView: some View {
        VStack(spacing: 0) {
            Text("search a song")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search songs or artists...", text: $searchText)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08))
            .clipShape(.rect(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.searchSongs(query: searchText)) { song in
                        songRow(song)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func songRow(_ song: Song) -> some View {
        HStack(spacing: 14) {
            Color(.systemGray5)
                .frame(width: 56, height: 56)
                .overlay {
                    AsyncImage(url: URL(string: song.albumArtURL)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artist.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.5)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                selectedSong = song
                withAnimation(.spring(duration: 0.3)) { step = 1 }
            } label: {
                Text("SHARE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.76, green: 0.38, blue: 0.35))
                    .clipShape(.capsule)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: selectedSong?.id)

            Text(song.duration)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Color.white.opacity(0.05)
                .frame(height: 0.5)
        }
    }
}
