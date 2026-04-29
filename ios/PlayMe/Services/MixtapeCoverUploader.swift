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
    private let bucketURL = "gs://rork-play-me.firebasestorage.app"

    private init() {}

    /// Center-crops to a square, scales so the longest edge is at most
    /// `maxEdge` points, then JPEG-encodes at `quality`.
    func prepareJPEG(from image: UIImage, maxEdge: CGFloat = 1024, quality: CGFloat = 0.8) -> Data? {
        let square = image.pm_squareCroppedCenter()
        let scaled = square.pm_scaled(maxEdge: maxEdge)
        return scaled.jpegData(compressionQuality: quality)
    }

    /// Uploads JPEG bytes and returns the Firebase Storage download URL.
    /// Progress is reported on the main actor when Firebase provides byte
    /// counts; callers may pass nil and keep the old spinner-only behavior.
    func uploadCoverJPEG(_ data: Data, ownerId: String, progress: ((Double) -> Void)? = nil) async throws -> String {
        let path = "mixtape-covers/\(ownerId)/\(UUID().uuidString).jpg"
        let storage = Storage.storage(url: bucketURL)
        let ref = storage.reference(withPath: path)
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = ref.putData(data, metadata: meta) { metadata, error in
                if let error {
                    cont.resume(throwing: Self.contextualError(
                        message: "Could not upload mixtape cover to \(self.bucketURL)/\(path).",
                        underlying: error
                    ))
                } else if metadata == nil {
                    cont.resume(throwing: Self.contextualError(
                        message: "Firebase Storage did not return upload metadata for \(self.bucketURL)/\(path).",
                        underlying: nil
                    ))
                } else {
                    DispatchQueue.main.async {
                        progress?(1)
                    }
                    cont.resume()
                }
            }
            if let progress {
                task.observe(.progress) { snapshot in
                    guard let p = snapshot.progress, p.totalUnitCount > 0 else { return }
                    let fraction = min(1, max(0, Double(p.completedUnitCount) / Double(p.totalUnitCount)))
                    DispatchQueue.main.async {
                        progress(fraction)
                    }
                }
            }
        }
        return try await downloadURLWithRetry(from: ref, path: path)
    }

    /// Convenience: prepare + upload using the signed-in user's uid.
    func uploadPickedImage(_ image: UIImage, progress: ((Double) -> Void)? = nil) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MixtapeCoverUploader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        guard let data = prepareJPEG(from: image) else {
            throw NSError(domain: "MixtapeCoverUploader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode image"])
        }
        return try await uploadCoverJPEG(data, ownerId: uid, progress: progress)
    }

    /// Firebase Storage can very occasionally report the upload completion
    /// before the download token lookup sees the object. Retry only the URL
    /// lookup so we don't duplicate uploads or orphan extra objects.
    private func downloadURLWithRetry(from ref: StorageReference, path: String) async throws -> String {
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                return try await ref.downloadURL().absoluteString
            } catch {
                lastError = error
                guard attempt < 3 else { break }
                try await Task.sleep(for: .milliseconds(250 * (attempt + 1)))
            }
        }
        throw Self.contextualError(
            message: "Upload completed, but Firebase could not find the object at \(bucketURL)/\(path).",
            underlying: lastError
        )
    }

    private static func contextualError(message: String, underlying: Error?) -> NSError {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let underlying {
            userInfo[NSUnderlyingErrorKey] = underlying
            userInfo[NSLocalizedFailureReasonErrorKey] = underlying.localizedDescription
        }
        return NSError(domain: "MixtapeCoverUploader", code: 3, userInfo: userInfo)
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
