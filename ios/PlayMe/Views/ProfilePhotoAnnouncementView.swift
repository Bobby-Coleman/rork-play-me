import SwiftUI

/// One-time "what's new" screen that tells existing users (who onboarded
/// before profile pictures shipped) that they can now add one. Shown once,
/// only to users without a photo. The primary button jumps straight into the
/// editor; "Maybe later" simply dismisses.
struct ProfilePhotoAnnouncementView: View {
    let initials: String
    let onAddPhoto: () -> Void
    let onDismiss: () -> Void

    private let preset = GradientAvatarPreset.all.first!

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 2)
                        .frame(width: 156, height: 156)
                        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 14)

                    GradientInitialsContent(preset: preset, initials: initials, fontSize: 64)
                        .frame(width: 144, height: 144)
                        .clipShape(Circle())
                }
                .overlay(alignment: .bottomTrailing) {
                    ZStack {
                        Circle().fill(Color.black).frame(width: 40, height: 40)
                        Circle().fill(AppAccentGradient.button).frame(width: 34, height: 34)
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                    }
                    .offset(x: 4, y: 4)
                }

                Text("New: profile pictures!")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)

                Text("Add a photo or a colorful initials style so your friends spot you instantly across RIFF.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 36)

                Text("Tap your profile picture anytime to change it.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 36)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    Button(action: onAddPhoto) {
                        Text("Add your photo")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppAccentGradient.button, in: Capsule())
                    }

                    Button(action: onDismiss) {
                        Text("Maybe later")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
    }
}
