import SwiftUI
import UIKit

/// UIKit bridge for choosing a mixtape cover. This intentionally uses
/// `UIImagePickerController` instead of `PhotosPicker`: `PhotosPicker`
/// has no built-in crop UI, while `allowsEditing = true` gives us Apple's
/// standard square pan/zoom crop flow for cover art.
struct MixtapeCoverImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onPicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, dismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onPicked: (UIImage) -> Void
        private let dismiss: () -> Void

        init(onPicked: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onPicked = onPicked
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let edited = info[.editedImage] as? UIImage {
                onPicked(edited)
            } else if let original = info[.originalImage] as? UIImage {
                onPicked(original)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
