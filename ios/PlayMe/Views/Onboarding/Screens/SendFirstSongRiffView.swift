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
    @State private var isPreparingSendSheet = false
    /// One-shot guard so the step only advances once, no matter which send
    /// path fired (direct search vs artist/album profile) or how many times
    /// the observed signal toggles.
    @State private var didComplete = false

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
                    openSendSheet()
                } label: {
                    VStack(spacing: 12) {
                        Text(isPreparingSendSheet ? "loading friends" : "search a song")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(theme.fg)
                        if isPreparingSendSheet {
                            ProgressView()
                                .tint(theme.fg)
                                .frame(height: 44)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundStyle(theme.fg)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isPreparingSendSheet)

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
            await appState.refreshFriends()
        }
        .onChange(of: appState.onboardingFirstSongShared) { _, shared in
            // Advancement is driven by this signal for every send path. The
            // direct path no longer calls onContinue itself, so there's no
            // double-advance; the guard covers any redundant toggles.
            guard shared, !didComplete else { return }
            didComplete = true
            onContinue()
        }
        .sheet(isPresented: $showSendSheet) {
            SendSongSheet(
                appState: appState,
                invitedContacts: appState.invitedContacts,
                onboardingRequestedUsers: appState.onboardingRequestedUsers
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

    private func openSendSheet() {
        guard !isPreparingSendSheet else { return }
        appState.onboardingFirstSongShared = false
        isPreparingSendSheet = true
        Task {
            await appState.refreshFriends()
            isPreparingSendSheet = false
            showSendSheet = true
        }
    }
}
