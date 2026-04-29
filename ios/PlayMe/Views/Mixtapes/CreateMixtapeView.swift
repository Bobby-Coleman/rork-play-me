import SwiftUI

/// Modal pushed from `SaveToMixtapeSheet` (or album-save) when the user
/// creates a new mixtape. Cover image is **required** — the user picks
/// from the photo library, we resize/crop/JPEG and upload to Firebase
/// Storage, then create the Firestore doc with the download URL.
struct CreateMixtapeView: View {
    /// When non-nil, the new mixtape is created with this song already
    /// added (save-to-mixtape flow). When nil, creates an empty mixtape
    /// (album-save "new mixtape" path).
    var seedSong: Song?
    @Bindable var appState: AppState
    /// Callback invoked once the mixtape is created (and the seed song
    /// added when applicable).
    var onCreated: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isCreating: Bool = false
    @State private var showCoverPicker: Bool = false
    @State private var uploadProgress: Double?
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, details }

    private let descriptionLimit = 300

    private var trimmed: String {
        appState.createMixtapeDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDetails: String? {
        let t = appState.createMixtapeDraft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private var canCreate: Bool {
        !trimmed.isEmpty && appState.createMixtapeDraft.coverImage != nil && !isCreating
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { appState.createMixtapeDraft.name },
            set: { appState.createMixtapeDraft.name = $0 }
        )
    }

    private var detailsBinding: Binding<String> {
        Binding(
            get: { appState.createMixtapeDraft.details },
            set: { appState.createMixtapeDraft.details = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            coverPickerSection
                                .padding(.top, 24)

                            if let seedSong {
                                VStack(spacing: 6) {
                                    Text("New mixtape")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text("Save \(seedSong.title) to a new collection.")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .padding(.horizontal, 24)
                            } else {
                            Text("New mixtape")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                            }

                            VStack(spacing: 12) {
                                AppTextField(
                                    "",
                                    text: nameBinding,
                                    prompt: Text("Mixtape name").foregroundColor(.white.opacity(0.4)),
                                    submitLabel: .done,
                                    onSubmit: {
                                        focusedField = nil
                                        UIApplication.pm_dismissKeyboard()
                                    }
                                )
                                .focused($focusedField, equals: .name)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white)
                                .tint(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.08))
                                .clipShape(.rect(cornerRadius: 14))

                                AppTextField(
                                    "",
                                    text: detailsBinding,
                                    prompt: Text("Description (optional)").foregroundColor(.white.opacity(0.4)),
                                    axis: .vertical,
                                    submitLabel: .done
                                )
                                .lineLimit(2...4)
                                .focused($focusedField, equals: .details)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .tint(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.08))
                                .clipShape(.rect(cornerRadius: 14))
                                .onChange(of: appState.createMixtapeDraft.details) { _, newValue in
                                    if newValue.contains("\n") {
                                        appState.createMixtapeDraft.details = newValue.replacingOccurrences(of: "\n", with: "")
                                        focusedField = nil
                                        UIApplication.pm_dismissKeyboard()
                                    } else if newValue.count > descriptionLimit {
                                        appState.createMixtapeDraft.details = String(newValue.prefix(descriptionLimit))
                                    }
                                }
                            }
                            .padding(.horizontal, 24)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.red.opacity(0.85))
                                    .padding(.horizontal, 24)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .appKeyboardDismiss()

                    Button {
                        Task { await create() }
                    } label: {
                        HStack {
                            Spacer()
                            if isCreating {
                                if let uploadProgress {
                                    ProgressView(value: uploadProgress)
                                        .tint(.black)
                                        .frame(width: 48)
                                } else {
                                    ProgressView().tint(.black)
                                }
                            } else {
                                Text("Create & Save")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Spacer()
                        }
                        .foregroundStyle(.black)
                        .padding(.vertical, 14)
                        .background(canCreate ? Color.white : Color.white.opacity(0.4))
                        .clipShape(.capsule)
                    }
                    .disabled(!canCreate)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .appKeyboardDismiss()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appState.createMixtapeDraft.clear()
                        dismiss()
                    }
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(.black)
        .interactiveDismissDisabled(true)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCoverPicker) {
            MixtapeCoverImagePicker { image in
                appState.createMixtapeDraft.coverImage = image
                errorMessage = nil
            }
            .ignoresSafeArea()
        }
    }

    private var coverPickerSection: some View {
        VStack(spacing: 12) {
            Button {
                focusedField = nil
                UIApplication.pm_dismissKeyboard()
                showCoverPicker = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 160, height: 160)

                    if let pickedImage = appState.createMixtapeDraft.coverImage {
                        Image(uiImage: pickedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 160, height: 160)
                            .clipShape(.rect(cornerRadius: 16))
                            .overlay(alignment: .topTrailing) {
                                Text("Change")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.55))
                                    .clipShape(.capsule)
                                    .padding(8)
                            }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.45))
                            Text("Add cover")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }

                    if isCreating {
                        Color.black.opacity(0.45)
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isCreating)

            Text("Cover is required")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func create() async {
        guard canCreate, let image = appState.createMixtapeDraft.coverImage else { return }
        isCreating = true
        uploadProgress = nil
        errorMessage = nil
        do {
            let coverURL = try await MixtapeCoverUploader.shared.uploadPickedImage(image) { progress in
                uploadProgress = progress
            }
            if let mixtape = await appState.mixtapeStore.create(name: trimmed, coverImageURL: coverURL) {
                if let seedSong {
                    await appState.mixtapeStore.addSong(seedSong, to: mixtape.id)
                }
                if let blurb = trimmedDetails {
                    await appState.mixtapeStore.updateDescription(mixtapeId: mixtape.id, to: blurb)
                }
                onCreated?()
                appState.createMixtapeDraft.clear()
                dismiss()
            } else {
                errorMessage = "Couldn't create mixtape. Check your connection and try again."
                isCreating = false
                uploadProgress = nil
            }
        } catch {
            errorMessage = "Couldn't upload cover. \(error.localizedDescription)"
            isCreating = false
            uploadProgress = nil
        }
    }
}
