import SwiftUI

struct AppUserAvatar: View {
    let user: AppUser?
    var size: CGFloat
    var foreground: Color = .white
    var background: Color = Color.white.opacity(0.12)
    var border: Color = Color.white.opacity(0.12)
    var borderWidth: CGFloat = 1
    var fontWeight: Font.Weight = .bold

    private var avatarURL: URL? {
        guard let raw = user?.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    private var initials: String {
        guard let user else { return "?" }
        return user.initials.isEmpty ? "?" : user.initials
    }

    var body: some View {
        ZStack {
            Circle().fill(background)

            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipped()
                    } else {
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(border, lineWidth: borderWidth))
        .fixedSize()
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: fontWeight))
            .foregroundStyle(foreground)
    }
}
