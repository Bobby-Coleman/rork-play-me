import SwiftUI

/// Onboarding step 6: "Send your first song".
///
/// Mirrors the main Discovery hero exactly — header + ambient album-art
/// grid + big "search a song" CTA — and hands the entire song + recipient
/// picking flow off to the shared `SendSongSheet`. The sheet is invoked
/// with the user's invited contacts so a freshly-registered user can
/// still send their first song to someone who hasn't joined yet. When
/// the send succeeds the sheet calls `onContinue`, advancing onboarding
/// to the next step.
struct SendFirstSongView: View {
    let appState: AppState
    let onContinue: () -> Void
    let onSkip: () -> Void
    /// Retained in the signature so `OnboardingView` doesn't need to
    /// change, but unused by the collapsed layout: there is no in-page
    /// "no friends yet" callout anymore.
    let onReopenInvites: () -> Void

    @State private var showSendSheet = false
    @State private var gridVM = SongGridViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Spacer(minLength: UIScreen.main.bounds.height * 0.04)

                ambientGrid

                Spacer(minLength: 24)

                searchCTA

                Spacer()

                Button("Skip for now", action: onSkip)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 16)
            }
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

    // MARK: - Layout

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Send your first song")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text("Pick a song, pick a friend, hit send. They'll get it on their home screen — even if they just got your invite and haven't joined yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineSpacing(2)
            }
            Spacer(minLength: 12)
            Button("Skip", action: onSkip)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    /// Taller-than-square grid that reads as distinct from the Discovery
    /// hero square while sharing the same component + scroll animation.
    /// Sizing is capped to screen HEIGHT as well as width so the grid +
    /// CTA + Skip always fit on one page on every device (SE through
    /// Pro Max).
    private var ambientGrid: some View {
        let screenW = UIScreen.main.bounds.width
        let screenH = UIScreen.main.bounds.height
        let width = min(screenW - 40, screenH * 0.42)
        let height = min(width * 1.35, screenH * 0.52)
        return AlbumArtGridBackgroundView(
            items: gridVM.dedupedDisplayItems,
            side: width,
            height: height
        )
        .frame(width: width, height: height)
    }

    private var searchCTA: some View {
        Button {
            showSendSheet = true
        } label: {
            VStack(spacing: 12) {
                Text("search a song")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
