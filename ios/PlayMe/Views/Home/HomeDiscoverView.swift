import SwiftUI

/// Root of the Home tab (leftmost). Pinterest-style staggered grid of
/// **curated mixtapes** from `DiscoverMixtapeFeedProvider`; tap opens
/// `MixtapeDetailView` (same sheet as the Mixtapes tab). Song playback
/// stays inside that detail surface (fullscreen feed).
struct HomeDiscoverView: View {
    let appState: AppState

    @State private var provider: any DiscoverMixtapeFeedProvider = MockDiscoverMixtapeFeedProvider()
    @State private var items: [Mixtape] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var detailMixtape: Mixtape?

    private let horizontalPadding: CGFloat = 16
    private let spacing: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let cellSize = PinterestGridLayout.cellSize(
                containerWidth: geo.size.width,
                horizontalPadding: horizontalPadding,
                spacing: spacing
            )

            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        Text("Curated mixtapes")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 12)
                            .padding(.bottom, 4)

                        if items.isEmpty && isLoading {
                            ProgressView()
                                .tint(.white)
                                .padding(.top, 80)
                        } else if items.isEmpty {
                            emptyState
                                .padding(.top, 80)
                        } else {
                            PinterestSquareGrid(
                                items: items,
                                cellSize: cellSize,
                                spacing: spacing
                            ) { mixtape, _ in
                                MixtapeGridCell(mixtape: mixtape, cornerRadius: 14)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        detailMixtape = mixtape
                                    }
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .refreshable { await refresh(force: true) }
            }
        }
        .task {
            await refresh(force: false)
        }
        .sheet(item: $detailMixtape) { mixtape in
            MixtapeDetailView(mixtape: mixtape, appState: appState)
                .presentationBackground(.black)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Discover")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text(errorMessage ?? "Pull to refresh. Add documents to `featured_mixtapes` in Firebase.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func refresh(force: Bool) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        let fresh = await provider.loadInitial()
        items = fresh
        if fresh.isEmpty, force {
            errorMessage = "No curated mixtapes yet."
        } else if !fresh.isEmpty {
            errorMessage = nil
        }
    }
}
