import SwiftUI

struct WidgetInstructionsView: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Text("add the widget\nto your home screen")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                VStack(spacing: 24) {
                    instructionRow(number: "1", text: "Hold down on any app\nto edit your Home Screen")
                    instructionRow(number: "2", text: "Tap the + button\nin the top left")
                    instructionRow(number: "3", text: "Search for \"Play Me\"\nand add the widget")
                }
                .padding(.horizontal, 32)

                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .frame(width: 100, height: 100)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("Widget")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }

                Spacer()

                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(.white)
                        .clipShape(.rect(cornerRadius: 26))
                }
                .padding(.horizontal, 40)

                Button("Skip for now", action: onDone)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 40)
            }
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(.white)
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .lineSpacing(4)
        }
    }
}
