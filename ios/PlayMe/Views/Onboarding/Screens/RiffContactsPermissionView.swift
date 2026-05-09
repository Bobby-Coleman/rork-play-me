import SwiftUI
import Contacts

/// Screen 10 — Contacts permission gate.
///
/// On first run we ask iOS for contacts access. If the user has already
/// granted (e.g. via the legacy `OnboardingInviteView`) we skip the
/// permission prompt and advance immediately. If they deny, we still
/// advance — the `PickFriendsView` will surface a helper message.
struct RiffContactsPermissionView: View {
    let stepIdx: Int
    let totalSteps: Int
    let onContinue: () -> Void
    let onBack: (() -> Void)?

    /// Bound by parent so the contact list survives the slide animation
    /// to the next screen.
    @Binding var contacts: [SimpleContact]
    @Binding var status: CNAuthorizationStatus

    var body: some View {
        RiffScreenChrome(stepIdx: stepIdx, totalSteps: totalSteps, onBack: onBack) {
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                RiffStagger(delay: 0.06) {
                    RiffHeadline(text: "You'll need friends to use RIFF.")
                }
                RiffStagger(delay: 0.18) {
                    RiffSubhead(text: "Allow contacts to find them. We don't store your contacts, and we never message anyone without you.")
                        .padding(.top, 16)
                }
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            RiffStagger(delay: 0.52) {
                RiffPrimaryButton(title: "Find my friends", action: requestAccess)
            }
        }
        .onAppear {
            // If contacts were already granted we still want them
            // hydrated by the time the user lands on PickFriendsView.
            if status == .authorized && contacts.isEmpty {
                contacts = ContactsService.shared.fetchContacts()
            }
            if status == .authorized {
                onContinue()
            }
        }
    }

    private func requestAccess() {
        if status == .authorized {
            onContinue()
            return
        }
        Task {
            let granted = await ContactsService.shared.requestAccess()
            await MainActor.run {
                status = granted ? .authorized : .denied
                if granted {
                    contacts = ContactsService.shared.fetchContacts()
                }
                onContinue()
            }
        }
    }
}
