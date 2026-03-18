import SwiftUI

struct OTPVerificationView: View {
    let onVerified: () -> Void

    @State private var code: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedIndex: Int?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("Enter the code")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                Text("We sent a 6-digit code to your phone")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 32)

                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { index in
                        TextField("", text: $code[index])
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .keyboardType(.numberPad)
                            .frame(width: 44, height: 52)
                            .background(Color.white.opacity(focusedIndex == index ? 0.15 : 0.08))
                            .clipShape(.rect(cornerRadius: 10))
                            .focused($focusedIndex, equals: index)
                            .onChange(of: code[index]) { _, newValue in
                                if newValue.count > 1 {
                                    code[index] = String(newValue.suffix(1))
                                }
                                if !newValue.isEmpty && index < 5 {
                                    focusedIndex = index + 1
                                }
                                if code.allSatisfy({ !$0.isEmpty }) {
                                    onVerified()
                                }
                            }
                    }
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear { focusedIndex = 0 }
    }
}
