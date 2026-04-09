import SwiftUI
import Combine

@MainActor
final class KeyboardObserver {
    static let shared = KeyboardObserver()

    let publisher: AnyPublisher<CGFloat, Never>

    private init() {
        publisher = Publishers.Merge(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
                .compactMap { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height },
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
                .map { _ in CGFloat(0) }
        )
        .removeDuplicates()
        .eraseToAnyPublisher()
    }
}
