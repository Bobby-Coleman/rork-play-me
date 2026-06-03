import SwiftUI
import UIKit

/// Wraps a picked image so it can drive a `fullScreenCover(item:)` crop step.
struct CropCandidate: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Circular crop step. The picked image is shown inside a square canvas with
/// a circular guide; the user pans and zooms to frame their face. "Use Photo"
/// renders the visible square region (the bounding box of the guide circle) to
/// a `UIImage`. We keep the stored crop square because every avatar surface in
/// the app already clips to a circle via `AppUserAvatar`.
struct CircleCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onCrop: (UIImage) -> Void

    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero

    private let cropSide: CGFloat = 300

    private var liveScale: CGFloat { max(1, scale * pinch) }
    private var liveOffset: CGSize {
        CGSize(width: offset.width + drag.width, height: offset.height + drag.height)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Move and scale")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 24)

                Spacer(minLength: 0)

                canvas
                    .frame(width: cropSide, height: cropSide)

                Spacer(minLength: 0)

                HStack(spacing: 14) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    Button(action: { onCrop(renderCrop()) }) {
                        Text("Use Photo")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white, in: Capsule())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var canvas: some View {
        ZStack {
            transformedImage(side: cropSide)
        }
        .frame(width: cropSide, height: cropSide)
        .clipped()
        .overlay(circleGuide)
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    },
                MagnificationGesture()
                    .updating($pinch) { value, state, _ in state = value }
                    .onEnded { value in
                        scale = max(1, scale * value)
                    }
            )
        )
    }

    private func transformedImage(side: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .scaleEffect(liveScale)
            .offset(liveOffset)
    }

    private var circleGuide: some View {
        ZStack {
            Color.black.opacity(0.55)
                .mask(
                    Rectangle()
                        .overlay(Circle().blendMode(.destinationOut))
                        .compositingGroup()
                )
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    @MainActor
    private func renderCrop() -> UIImage {
        let content = ZStack {
            transformedImage(side: cropSide)
        }
        .frame(width: cropSide, height: cropSide)
        .clipped()

        let renderer = ImageRenderer(content: content)
        renderer.scale = 512 / cropSide
        return renderer.uiImage ?? image
    }
}

/// `UIImagePickerController` bridge with editing disabled: it returns the
/// untouched original image so our own `CircleCropView` can drive the crop.
struct RawPhotoPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onPicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, dismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
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
            if let original = info[.originalImage] as? UIImage {
                onPicked(original)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
