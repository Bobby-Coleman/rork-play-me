import SwiftUI
import UIKit

struct ProfilePhotoView: View {
    @Bindable var appState: AppState
    let firstName: String
    let lastName: String
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    @State private var selectedID: String?
    @State private var uploadedImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var cropCandidate: CropCandidate?
    @State private var isSaving = false
    @State private var uploadProgress: Double?
    @State private var errorMessage: String?

    private var fullNameInitials: String {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()
        let combined = "\(first)\(last)"
        return combined.isEmpty ? "?" : combined
    }

    private var options: [AvatarOption] {
        var arr: [AvatarOption] = [AvatarOption(id: "upload", kind: .upload)]
        arr += GradientAvatarPreset.all.map { AvatarOption(id: "g.\($0.id)", kind: .gradient($0)) }
        arr.append(AvatarOption(id: "plain", kind: .plainInitials))
        return arr
    }

    private var selectedOption: AvatarOption {
        options.first { $0.id == selectedID } ?? options[0]
    }

    private var isUploadSelected: Bool {
        if case .upload = selectedOption.kind { return true }
        return false
    }

    private var canContinue: Bool {
        !isSaving
    }

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack, contentTopPadding: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    RiffWordmark(size: 38)
                    Spacer()
                }
                .padding(.top, 18)

                RiffHeadline(text: "Choose your profile picture.")
                    .padding(.top, 28)

                RiffSubhead(text: "This is how friends will spot you in RIFF.")
                    .padding(.top, 16)

                Spacer(minLength: 0)

                carousel
                    .frame(height: 280)

                VStack(spacing: 8) {
                    Text(titleText)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitleText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

                pageDots
                    .padding(.top, 14)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }

                Spacer(minLength: 0)
            }
        } footer: {
            RiffPrimaryButton(
                title: buttonTitle,
                disabled: !canContinue,
                action: {
                    if isUploadSelected, uploadedImage == nil {
                        showPhotoPicker = true
                    } else {
                        Task { await saveSelection() }
                    }
                }
            )
        }
        .riffTheme(.black)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPhotoPicker) {
            RawPhotoPicker { image in
                cropCandidate = CropCandidate(image: image)
            }
        }
        .fullScreenCover(item: $cropCandidate) { candidate in
            CircleCropView(
                image: candidate.image,
                onCancel: { cropCandidate = nil },
                onCrop: { cropped in
                    uploadedImage = cropped
                    selectedID = "upload"
                    errorMessage = nil
                    cropCandidate = nil
                }
            )
        }
        .onAppear {
            if selectedID == nil { selectedID = options.first?.id }
        }
    }

    private var titleText: String {
        switch selectedOption.kind {
        case .upload: return "Upload Photo"
        case .gradient: return "Initials"
        case .plainInitials: return "Initials"
        }
    }

    private var subtitleText: String {
        switch selectedOption.kind {
        case .upload:
            return uploadedImage == nil ? "tap the circle to choose" : "tap to change"
        case .gradient:
            return "your initials on a gradient"
        case .plainInitials:
            return "your first and last initial"
        }
    }

    private var buttonTitle: String {
        if isSaving {
            if let uploadProgress {
                return "Saving \(Int(uploadProgress * 100))%"
            }
            return "Saving..."
        }
        if isUploadSelected, uploadedImage == nil {
            return "Choose Photo"
        }
        return "Continue"
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(options) { option in
                    optionCircle(option)
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.82)
                                .opacity(phase.isIdentity ? 1 : 0.55)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 78, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selectedID, anchor: .center)
        .scrollIndicators(.hidden)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(options) { option in
                Capsule()
                    .fill(option.id == selectedID ? Color.white.opacity(0.9) : Color.white.opacity(0.18))
                    .frame(width: option.id == selectedID ? 22 : 6, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.72), value: selectedID)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func optionCircle(_ option: AvatarOption) -> some View {
        let side: CGFloat = 196
        return Button {
            if case .upload = option.kind, option.id == selectedID {
                showPhotoPicker = true
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selectedID = option.id
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 14)

                optionContent(option)
                    .frame(width: side - 12, height: side - 12)
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    @ViewBuilder
    private func optionContent(_ option: AvatarOption) -> some View {
        switch option.kind {
        case .upload:
            if let uploadedImage {
                Image(uiImage: uploadedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 34, weight: .semibold))
                        Text("Upload a photo")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                }
            }
        case .gradient(let preset):
            GradientInitialsContent(preset: preset, initials: fullNameInitials)
        case .plainInitials:
            ZStack {
                Color.white
                Text(fullNameInitials)
                    .font(.system(size: 58, weight: .black))
                    .foregroundStyle(.black)
            }
        }
    }

    private func saveSelection() async {
        errorMessage = nil
        isSaving = true
        uploadProgress = nil
        defer {
            isSaving = false
            uploadProgress = nil
        }

        let imageToSave: UIImage?
        switch selectedOption.kind {
        case .upload:
            imageToSave = uploadedImage
        case .gradient(let preset):
            imageToSave = renderGradientAvatar(preset)
        case .plainInitials:
            imageToSave = nil
        }

        let ok = await appState.updateProfilePhoto(image: imageToSave) { progress in
            uploadProgress = progress
        }
        if ok {
            onContinue()
        } else {
            errorMessage = appState.registrationError ?? "Could not save your profile picture. Please try again."
        }
    }

    @MainActor
    private func renderGradientAvatar(_ preset: GradientAvatarPreset, size: CGFloat = 512) -> UIImage? {
        let content = GradientInitialsContent(preset: preset, initials: fullNameInitials, fontSize: size * 0.42)
            .frame(width: size, height: size)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.uiImage
    }
}

private struct AvatarOption: Identifiable {
    enum Kind {
        case upload
        case gradient(GradientAvatarPreset)
        case plainInitials
    }
    let id: String
    let kind: Kind
}

/// A solid gradient fill with the user's initials centered on top. Reused for
/// the carousel preview and for the rendered avatar image that gets uploaded.
struct GradientInitialsContent: View {
    let preset: GradientAvatarPreset
    let initials: String
    var fontSize: CGFloat = 58

    var body: some View {
        ZStack {
            preset.gradient
            Text(initials)
                .font(.system(size: fontSize, weight: .black))
                .foregroundStyle(preset.textColor)
                .minimumScaleFactor(0.5)
        }
    }
}

/// Preset gradient backgrounds for initials-based avatars. Each carries an
/// explicit contrast color so the initials stay legible.
struct GradientAvatarPreset: Identifiable, Hashable {
    let id: String
    let colors: [Color]
    let textColor: Color

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let all: [GradientAvatarPreset] = [
        GradientAvatarPreset(
            id: "lilac",
            colors: [AppAccentGradient.lilac, AppAccentGradient.pink, AppAccentGradient.peach],
            textColor: .black
        ),
        GradientAvatarPreset(
            id: "indigo",
            colors: [Color(red: 0.36, green: 0.31, blue: 0.86), Color(red: 0.58, green: 0.36, blue: 0.92)],
            textColor: .white
        ),
        GradientAvatarPreset(
            id: "sunset",
            colors: [Color(red: 0.98, green: 0.45, blue: 0.36), Color(red: 0.96, green: 0.27, blue: 0.55)],
            textColor: .white
        ),
    ]
}
