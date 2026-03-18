import SwiftUI

struct PhoneEntryView: View {
    @Binding var phoneNumber: String
    let onNext: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            BlobShape()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.06), Color.clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 200
                    )
                )
                .frame(width: 350, height: 350)
                .offset(y: -120)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("What's your\nphone number?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 24)

                HStack(spacing: 12) {
                    TextField("(555) 000-0000", text: $phoneNumber)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($isFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 12))

                    Button(action: onNext) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 48, height: 48)
                            .background(.white)
                            .clipShape(Circle())
                    }
                    .disabled(phoneNumber.count < 7)
                    .opacity(phoneNumber.count < 7 ? 0.4 : 1)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear { isFocused = true }
    }
}
