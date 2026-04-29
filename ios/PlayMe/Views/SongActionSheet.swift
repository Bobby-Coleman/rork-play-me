import SwiftUI

/// Canonical Song Action View host.
///
/// Every full-screen song surface in the app (search results, artist page,
/// album tracklists, feed card taps, share buttons, mini-player, chat song
/// bubbles, profile history) presents this sheet. It's the single destination
/// for "open a song" — preview/scrub, friend multi-select, send, and
/// open-in-service all live in one place.
///
/// This is deliberately a thin wrapper: `FriendSelectorView` already contains
/// the entire interactive surface. `SongActionSheet` just gives it a host
/// context with dismiss handling so it can be presented from anywhere
/// without needing bespoke navigation glue at each call site.
struct SongActionSheet: View {
    let song: Song
    let appState: AppState
    /// Optional share context. When present, the sheet is acting as the
    /// destination for a feed card / history tap and we preserve the share
    /// so any future metadata-aware features (likes tied to a share, etc.)
    /// can read it. FriendSelectorView itself doesn't need it today, but
    /// keeping the parameter avoids churning call sites later.
    var share: SongShare? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FriendSelectorView(
                item: .song(song),
                appState: appState,
                shareId: share?.id,
                onBack: { dismiss() },
                onSent: { dismiss() }
            )
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
}
