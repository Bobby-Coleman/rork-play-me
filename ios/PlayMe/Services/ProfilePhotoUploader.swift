import Foundation
import UIKit
import FirebaseAuth
import FirebaseStorage

final class ProfilePhotoUploader: @unchecked Sendable {
    static let shared = ProfilePhotoUploader()
    private let bucketURL = "gs://rork-play-me.firebasestorage.app"

    private init() {}

    func prepareJPEG(from image: UIImage, maxEdge: CGFloat = 512, quality: CGFloat = 0.82) -> Data? {
        let square = image.pm_profileSquareCroppedCenter()
        let scaled = square.pm_profileScaled(maxEdge: maxEdge)
        return scaled.jpegData(compressionQuality: quality)
    }

    func uploadProfileJPEG(_ data: Data, ownerId: String, progress: ((Double) -> Void)? = nil) async throws -> String {
        let path = "profile-photos/\(ownerId)/avatar.jpg"
        let storage = Storage.storage(url: bucketURL)
        let ref = storage.reference(withPath: path)
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = ref.putData(data, metadata: meta) { metadata, error in
                if let error {
                    cont.resume(throwing: Self.contextualError(
                        message: "Could not upload profile photo to \(self.bucketURL)/\(path).",
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

    func uploadPickedImage(_ image: UIImage, progress: ((Double) -> Void)? = nil) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ProfilePhotoUploader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        guard let data = prepareJPEG(from: image) else {
            throw NSError(domain: "ProfilePhotoUploader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode image"])
        }
        return try await uploadProfileJPEG(data, ownerId: uid, progress: progress)
    }

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
        return NSError(domain: "ProfilePhotoUploader", code: 3, userInfo: userInfo)
    }
}

private extension UIImage {
    func pm_profileSquareCroppedCenter() -> UIImage {
        guard let cg = cgImage else { return self }
        let pixelW = CGFloat(cg.width)
        let pixelH = CGFloat(cg.height)
        let side = min(pixelW, pixelH)
        let x = (pixelW - side) / 2
        let y = (pixelH - side) / 2
        guard let cropped = cg.cropping(to: CGRect(x: x, y: y, width: side, height: side)) else { return self }
        return UIImage(cgImage: cropped, scale: 1, orientation: imageOrientation)
    }

    func pm_profileScaled(maxEdge: CGFloat) -> UIImage {
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
