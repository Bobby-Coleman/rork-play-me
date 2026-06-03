import SwiftUI
import UIKit

/// Post-onboarding editor for changing or removing your profile picture.
/// Reuses the onboarding `ProfilePhotoPicker` so the experience is identical,
/// and adds an explicit destructive "Remove current photo" action. Both Save
/// and Remove route through `appState.updateProfilePhoto(image:)` (nil clears
/// the stored photo).
struct ProfilePhotoEditorView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: String?
    @State private var uploadedImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var isSaving = false
    @State private var uploadProgress: Double?
    @State private var errorMessage: String?

    private var initials: String {
        profileInitials(
            firstName: appState.currentUser?.firstName ?? "",
            lastName: appState.currentUser?.lastName ?? ""
        )
    }

    private var hasExistingPhoto: Bool {
        let url = appState.currentUser?.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        return !(url ?? "").isEmpty
    }

    private var selectedOption: AvatarOption {
        let options = makeProfileAvatarOptions()
        return options.first { $0.id == selectedID } ?? options[0]
    }

    private var isUploadSelected: Bool {
        if case .upload = selectedOption.kind { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer(minLength: 8)

                    ProfilePhotoPicker(
                        initials: initials,
                        selectedID: $selectedID,
                        uploadedImage: $uploadedImage,
                        showPhotoPicker: $showPhotoPicker,
                        isSaving: isSaving
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 12) {
                        Button(action: primaryAction) {
                            Text(primaryTitle)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppAccentGradient.button, in: Capsule())
                                .opacity(isSaving ? 0.6 : 1)
                        }
                        .disabled(isSaving)

                        if hasExistingPhoto {
                            Button(role: .destructive, action: { Task { await removePhoto() } }) {
                                Text("Remove current photo")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.red.opacity(0.9))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .disabled(isSaving)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Profile Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                        .disabled(isSaving)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var primaryTitle: String {
        if isSaving {
            if let uploadProgress {
                return "Saving \(Int(uploadProgress * 100))%"
            }
            return "Saving..."
        }
        if isUploadSelected, uploadedImage == nil {
            return "Choose Photo"
        }
        return "Save"
    }

    private func primaryAction() {
        if isUploadSelected, uploadedImage == nil {
            showPhotoPicker = true
        } else {
            Task { await save() }
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        uploadProgress = nil
        defer {
            isSaving = false
            uploadProgress = nil
        }

        let imageToSave = renderSelectedAvatarImage(
            selectedID: selectedID,
            uploadedImage: uploadedImage,
            initials: initials
        )

        let ok = await appState.updateProfilePhoto(image: imageToSave) { progress in
            uploadProgress = progress
        }
        if ok {
            dismiss()
        } else {
            errorMessage = appState.registrationError ?? "Could not save your profile picture. Please try again."
        }
    }

    private func removePhoto() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let ok = await appState.updateProfilePhoto(image: nil)
        if ok {
            dismiss()
        } else {
            errorMessage = appState.registrationError ?? "Could not remove your profile picture. Please try again."
        }
    }
}
