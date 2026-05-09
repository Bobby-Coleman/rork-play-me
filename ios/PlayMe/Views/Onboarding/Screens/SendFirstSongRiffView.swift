import SwiftUI

/// Screen 15 — Send your first song (final step of the new flow).
///
/// Thin wrapper that keeps the existing `SendFirstSongView` body
/// (search CTA + ambient album-art grid + `SendSongSheet` hookup) but
/// drops it inside `RiffScreenChrome` so it inherits the active theme
/// instead of the hardcoded black. The actual send-song UI is still the
/// existing `SendSongSheet` per the design spec.
struct SendFirstSongRiffView: View {
    let appState: AppState
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onSkip: () -> Void
    let onReopenInvites: () -> Void
    let onBack: (() -> Void)?

    @State private var showSendSheet = false
    @State private var gridVM = SongGridViewModel()

    @Environment(\.riffTheme) private var theme

    var body: some View {
        RiffScreenChrome(
            stepIdx: stepIdx,
            totalSteps: totalSteps,
            onBack: onBack,
            horizontalPadding: 20
        ) {
            VStack(alignment: .leading, spacing: 8) {
                RiffStagger(delay: 0.06) {
                    Text("Send your first song")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(theme.fg)
                }
                RiffStagger(delay: 0.18) {
                    Text("Pick a song, pick a friend, hit send. They'll get it on their home screen — even if they just got your invite and haven't joined yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.fg.opacity(0.55))
                        .lineSpacing(2)
                }
            }
            .padding(.top, 8)

            VStack(spacing: 0) {
                Spacer(minLength: 12)
                ambientGrid
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 18)

                Button {
                    showSendSheet = true
                } label: {
                    VStack(spacing: 12) {
                        Text("search a song")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(theme.fg)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(theme.fg)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 12)
            }
            .frame(maxHeight: .infinity)
        } footer: {
            Button("Skip for now", action: onSkip)
                .font(.system(size: 13))
                .foregroundStyle(theme.fg.opacity(0.4))
        }
        .task {
            await gridVM.loadIfNeeded()
        }
        .sheet(isPresented: $showSendSheet) {
            SendSongSheet(
                appState: appState,
                invitedContacts: appState.invitedContacts,
                onboardingRequestedUsers: appState.onboardingRequestedUsers,
                onSent: onContinue
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var ambientGrid: some View {
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height
        let width = min(screenW - 40, screenH * 0.36)
        let height = min(width * 1.35, screenH * 0.44)
        return AlbumArtGridBackgroundView(
            items: gridVM.dedupedDisplayItems,
            side: width,
            height: height
        )
        .frame(width: width, height: height)
    }
}
