import Foundation
import UIKit
import FirebaseAuth
import FirebaseStorage

/// Single pipeline for mixtape cover images: square-crop, resize,
/// JPEG-compress, then upload to Firebase Storage under
/// `mixtape-covers/{uid}/{uuid}.jpg`. All create-mixtape flows go through
/// this type.
final class MixtapeCoverUploader: @unchecked Sendable {
    static let shared = MixtapeCoverUploader()

    private init() {}

    /// Center-crops to a square, scales so the longest edge is at most
    /// `maxEdge` points, then JPEG-encodes at `quality`.
    func prepareJPEG(from image: UIImage, maxEdge: CGFloat = 1024, quality: CGFloat = 0.8) -> Data? {
        let square = image.pm_squareCroppedCenter()
        let scaled = square.pm_scaled(maxEdge: maxEdge)
        return scaled.jpegData(compressionQuality: quality)
    }

    /// Uploads JPEG bytes and returns the Firebase Storage download URL.
    func uploadCoverJPEG(_ data: Data, ownerId: String) async throws -> String {
        let path = "mixtape-covers/\(ownerId)/\(UUID().uuidString).jpg"
        let ref = Storage.storage().reference(withPath: path)
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.putData(data, metadata: meta) { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
        return try await ref.downloadURL().absoluteString
    }

    /// Convenience: prepare + upload using the signed-in user's uid.
    func uploadPickedImage(_ image: UIImage) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MixtapeCoverUploader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        guard let data = prepareJPEG(from: image) else {
            throw NSError(domain: "MixtapeCoverUploader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode image"])
        }
        return try await uploadCoverJPEG(data, ownerId: uid)
    }
}

private extension UIImage {
    /// Crops to the center square in pixel space.
    func pm_squareCroppedCenter() -> UIImage {
        guard let cg = cgImage else { return self }
        let pixelW = CGFloat(cg.width)
        let pixelH = CGFloat(cg.height)
        let side = min(pixelW, pixelH)
        let x = (pixelW - side) / 2
        let y = (pixelH - side) / 2
        guard let cropped = cg.cropping(to: CGRect(x: x, y: y, width: side, height: side)) else { return self }
        return UIImage(cgImage: cropped, scale: 1, orientation: imageOrientation)
    }

    /// Uniform scale-down so max(width,height) <= maxEdge (in points of the returned image).
    func pm_scaled(maxEdge: CGFloat) -> UIImage {
        let w = size.width
        let h = size.height
        let longest = max(w, h)
        guard longest > maxEdge, longest > 0 else { return self }
        let ratio = maxEdge / longest
        let nw = max(1, w * ratio)
        let nh = max(1, h * ratio)
        let r = UIGraphicsImageRenderer(size: CGSize(width: nw, height: nh))
        return r.image { _ in
            draw(in: CGRect(origin: .zero, size: CGSize(width: nw, height: nh)))
        }
    }
}
