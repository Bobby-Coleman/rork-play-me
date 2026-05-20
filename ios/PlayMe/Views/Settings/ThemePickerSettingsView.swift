import SwiftUI

/// Post-onboarding theme re-picker. Sits at Settings → Appearance → Theme.
/// Mirrors the onboarding theme picker but lays out as a static grid so the
/// user can scan all four palettes side by side. Tapping a swatch updates
/// `appState.appTheme` immediately; the change propagates through
/// `@Environment(\.riffTheme)` and the whole app re-tints without an app
/// restart.
struct ThemePickerSettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.riffTheme) private var theme

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(theme.fg)
                    Text("Pick a palette. The whole app re-tints — backgrounds, send buttons, accept pills, message bubbles.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.sub)
                }
                .padding(.horizontal, 20)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(RiffTheme.all) { swatch in
                        swatchCard(swatch)
                    }
                }
                .padding(.horizontal, 20)

                preview
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 24)
            }
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(theme.toolbarColorScheme, for: .navigationBar)
    }

    private func swatchCard(_ swatch: RiffTheme) -> some View {
        let selected = swatch == appState.appTheme
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.18)) {
                appState.appTheme = swatch
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(swatch.bg)
                        .frame(height: 120)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aa")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(swatch.fg)
                        HStack(spacing: 6) {
                            Capsule()
                                .fill(swatch.accent)
                                .frame(width: 36, height: 10)
                            Capsule()
                                .fill(swatch.fg.opacity(0.18))
                                .frame(width: 22, height: 10)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? theme.fg : theme.border, lineWidth: selected ? 2 : 1)
                )

                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? theme.accent : theme.faint)
                    Text(swatch.displayName)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(theme.fg)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(theme.sub)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 8) {
                    Spacer(minLength: 32)
                    Text("New track?")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.accentOn)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(theme.accent, in: .rect(cornerRadius: 16, style: .continuous))
                }

                HStack(alignment: .bottom, spacing: 8) {
                    Text("Listening now")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.fg)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(theme.softBg, in: .rect(cornerRadius: 16, style: .continuous))
                    Spacer(minLength: 32)
                }

                HStack(spacing: 10) {
                    Text("Send")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.accentOn)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.accent, in: .capsule)
                    Text("Save")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.fg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.softBg, in: .capsule)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
    }
}
