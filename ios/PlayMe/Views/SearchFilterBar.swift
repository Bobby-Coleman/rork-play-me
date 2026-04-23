import SwiftUI
import UIKit

/// Horizontal pill row bound to an external `SearchFilter` binding. Pills
/// animate the underline and fire a light haptic on selection — matches
/// the feel of Spotify's filter chips.
struct SearchFilterBar: View {
    @Binding var selection: SearchFilter
    /// Caller-provided callback invoked after the selection changes. The
    /// binding itself is the source of truth; this is purely for
    /// side-effects (e.g. scroll to top when user flips tabs).
    var onSelectionChange: ((SearchFilter) -> Void)? = nil

    @Namespace private var underline

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilter.allCases) { filter in
                    pill(for: filter)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func pill(for filter: SearchFilter) -> some View {
        let isActive = selection == filter
        Button {
            guard selection != filter else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.18)) {
                selection = filter
            }
            onSelectionChange?(filter)
        } label: {
            Text(filter.displayLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isActive ? Color.white : Color.white.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isActive ? 0 : 0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
