import SwiftUI
import UIKit

extension UIApplication {
    /// Standard app-wide keyboard dismissal hook.
    @MainActor
    static func pm_dismissKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct AppKeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.pm_dismissKeyboard()
                    }
            }
    }
}

extension View {
    /// Tap empty/background space to dismiss the current keyboard.
    func appKeyboardDismiss() -> some View {
        modifier(AppKeyboardDismissModifier())
    }
}

/// ScrollView wrapper for input-heavy screens. It centralizes interactive
/// keyboard dismissal instead of relying on each screen to remember it.
struct AppScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let showsIndicators: Bool
    private let content: () -> Content

    init(
        _ axes: Axis.Set = .vertical,
        showsIndicators: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content
    }

    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            content()
        }
        .scrollDismissesKeyboard(.interactively)
        .appKeyboardDismiss()
    }
}

/// Standard text-input primitive. Styling stays at the call site so existing
/// screens keep their look while sharing submit/dismiss behavior.
struct AppTextField: View {
    private let title: String
    @Binding private var text: String
    private let prompt: Text?
    private let axis: Axis
    private let submitLabel: SubmitLabel
    private let onSubmit: (() -> Void)?

    init(
        _ title: String,
        text: Binding<String>,
        prompt: Text? = nil,
        axis: Axis = .horizontal,
        submitLabel: SubmitLabel = .done,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.axis = axis
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    var body: some View {
        TextField(title, text: $text, prompt: prompt, axis: axis)
            .submitLabel(submitLabel)
            .onSubmit {
                if let onSubmit {
                    onSubmit()
                } else {
                    UIApplication.pm_dismissKeyboard()
                }
            }
    }
}
