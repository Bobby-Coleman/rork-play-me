import SwiftUI

struct NameEntryView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    let onComplete: () -> Void
    var onBack: (() -> Void)? = nil

    @FocusState private var focusedField: Field?

    private enum Field { case first, last }

    private var canContinue: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let onBack {
                VStack {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.top, 8)
                    Spacer()
                }
            }

            BlobShape()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.05), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 180
                    )
                )
                .frame(width: 300, height: 300)
                .offset(y: -140)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("What's your\nname?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 24)

                HStack(spacing: 12) {
                    VStack(spacing: 12) {
                        TextField("First name", text: $firstName)
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .first)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .last }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 12))

                        TextField("Last name", text: $lastName)
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .textContentType(.familyName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .last)
                            .submitLabel(.continue)
                            .onSubmit { if canContinue { onComplete() } }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 12))
                    }

                    Button(action: { if canContinue { onComplete() } }) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 48, height: 48)
                            .background(.white)
                            .clipShape(Circle())
                    }
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.4)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear { focusedField = .first }
    }
}
