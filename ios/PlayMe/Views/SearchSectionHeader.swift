import SwiftUI

/// Section eyebrow rendered above grouped result blocks (Artists/Songs/
/// Albums). Optional "See all" chevron on the trailing edge jumps to the
/// matching filter tab.
struct SearchSectionHeader: View {
    let title: String
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            if let onSeeAll {
                Button(action: onSeeAll) {
                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
