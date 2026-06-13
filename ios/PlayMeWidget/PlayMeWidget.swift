import WidgetKit
import SwiftUI
import UIKit

private nonisolated let widgetAppGroupId = "group.app.rork.playme.shared"
private nonisolated let widgetStyleKey = "widgetStyle"
private nonisolated let widgetStyleEpochKey = "widgetStyleEpoch"

/// Mirror of the main app's `WidgetStyle` (extensions can't import the app
/// target). Raw values must match `WidgetSharedConstants.Key.widgetStyle`
/// writes from the app. A legacy stored "cdDark" decodes to nil and falls
/// back to `.cd` (the dark case style was removed).
nonisolated enum WidgetStyle: String {
    case cd
    case classic
}

nonisolated struct SongEntry: TimelineEntry {
    let date: Date
    let songTitle: String
    let songArtist: String
    let albumImage: UIImage?
    let senderFirstName: String
    let senderAvatarImage: UIImage?
    let note: String?
    let shareId: String?
    /// False before the first real song is received. Drives the
    /// "Tap to set up" empty state so a fresh widget never looks blank.
    let hasSong: Bool
    /// User-selected look (Settings / onboarding). Defaults to CD.
    let style: WidgetStyle
    /// Bumped on every style change so WidgetKit busts cached timelines.
    let styleEpoch: Int
}

nonisolated struct SongProvider: TimelineProvider {
    func placeholder(in context: Context) -> SongEntry {
        SongEntry(
            date: .now,
            songTitle: "Can't Help Myself",
            songArtist: "Kita Alexander",
            albumImage: nil,
            senderFirstName: "Molly",
            senderAvatarImage: nil,
            note: "this song reminds me of you",
            shareId: nil,
            hasSong: true,
            style: .cd,
            styleEpoch: 0
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SongEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SongEntry>) -> Void) {
        let entry = loadEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadEntry() -> SongEntry {
        let defaults = UserDefaults(suiteName: widgetAppGroupId)
        let storedTitle = defaults?.string(forKey: "widgetSongTitle")
        let hasSong = !(storedTitle?.isEmpty ?? true)
        let title = storedTitle ?? "Play Me"
        let artist = defaults?.string(forKey: "widgetSongArtist") ?? "Open the app to see songs"
        let firstName = defaults?.string(forKey: "widgetSenderFirstName") ?? ""
        let note = defaults?.string(forKey: "widgetNote")
        let shareId = defaults?.string(forKey: "widgetShareId")
        let styleRaw = defaults?.string(forKey: widgetStyleKey) ?? ""
        // Legacy "cdDark" (removed style) falls back to CD.
        let style: WidgetStyle = {
            if styleRaw == "cdDark" { return .cd }
            return WidgetStyle(rawValue: styleRaw) ?? .cd
        }()
        let styleEpoch = defaults?.integer(forKey: widgetStyleEpochKey) ?? 0

        var albumImage: UIImage? = nil
        var senderAvatarImage: UIImage? = nil
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: widgetAppGroupId) {
            let imageFile = containerURL.appendingPathComponent("widgetAlbumArt.jpg")
            albumImage = UIImage(contentsOfFile: imageFile.path)
            let avatarFile = containerURL.appendingPathComponent("widgetSenderAvatar.jpg")
            senderAvatarImage = UIImage(contentsOfFile: avatarFile.path)
        }

        return SongEntry(
            date: .now,
            songTitle: title,
            songArtist: artist,
            albumImage: albumImage,
            senderFirstName: firstName,
            senderAvatarImage: senderAvatarImage,
            note: note,
            shareId: shareId,
            hasSong: hasSong,
            style: style,
            styleEpoch: styleEpoch
        )
    }
}

/// Loads the bundled CD case photo for the widget extension. Asset-catalog
/// `Image("CDCase")` inside `containerBackground` is unreliable in extensions;
/// foreground `Image(uiImage:)` matches the in-app carousel and Classic's path.
private enum CDCaseImageLoader {
    static var image: UIImage? {
        UIImage(named: "CDCase", in: .main, compatibleWith: nil)
    }
}

struct PlayMeWidgetView: View {
    var entry: SongEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetContentMargins) private var contentMargins

    private var isSmall: Bool { family == .systemSmall }

    private static let discCenterX: CGFloat = 0.508
    private static let discCenterY: CGFloat = 0.500
    private static let discDiameterRatio: CGFloat = 0.870
    private static let hubHoleRatio: CGFloat = 0.24
    private static let nameMax = 9

    var body: some View {
        Group {
            if !entry.hasSong {
                emptyBody
            } else if entry.style == .classic {
                classicBody
            } else {
                cdSongBody
            }
        }
    }

    private var emptyBody: some View {
        VStack(spacing: 4) {
            Text("RIFF")
                .font(.system(size: isSmall ? 22 : 28, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white)
            Text("Tap to set up")
                .font(.system(size: isSmall ? 11 : 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            Color(white: 0.08)
        }
        .widgetURL(URL(string: "playme://"))
    }

    /// CD case with composited disc — mirrors the in-app carousel: case
    /// photo in the foreground `ZStack`, solid fallback in
    /// `containerBackground`, disc + glare + pill layered on top.
    private var cdSongBody: some View {
        GeometryReader { geo in
            let discD = geo.size.width * Self.discDiameterRatio
            let discCenter = CGPoint(
                x: geo.size.width * Self.discCenterX,
                y: geo.size.height * Self.discCenterY
            )
            let em = max(8, geo.size.width * 0.05)

            ZStack {
                cdCaseBackground(width: geo.size.width, height: geo.size.height)

                if let art = entry.albumImage {
                    disc(art: art, diameter: discD)
                        .position(discCenter)
                }

                caseGlare
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .overlay(alignment: .bottom) {
                senderPill(em: em)
                    .frame(maxWidth: geo.size.width * 0.9)
                    .padding(.bottom, geo.size.height * 0.054)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            Color.white
        }
        .widgetURL(widgetDeepLink)
    }

    @ViewBuilder
    private func cdCaseBackground(width: CGFloat, height: CGFloat) -> some View {
        if let uiImage = CDCaseImageLoader.image {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
                .widgetAccentable(false)
        } else {
            Color(white: 0.92)
                .frame(width: width, height: height)
        }
    }

    private var classicBody: some View {
        let label = pillLabel
        return ZStack(alignment: .bottomLeading) {
            Color.clear

            if !entry.senderFirstName.isEmpty || !(entry.note ?? "").isEmpty {
                HStack(alignment: .bottom, spacing: 5) {
                    if !entry.senderFirstName.isEmpty {
                        classicSenderBubble
                    }

                    HStack(spacing: 4) {
                        Text(label.text)
                            .font(.system(size: isSmall ? 10 : 12, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(label.isMessage ? (isSmall ? 4 : 6) : 2)
                            .minimumScaleFactor(label.isMessage ? 1 : 0.85)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !label.isMessage {
                            Image(systemName: "heart.fill")
                                .font(.system(size: isSmall ? 8.5 : 10, weight: .semibold))
                                .foregroundStyle(Color(white: 0.82).opacity(0.55))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color(white: 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(contentMargins)
            }
        }
        .containerBackground(for: .widget) {
            if let uiImage = entry.albumImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(white: 0.08)
            }
        }
        .widgetURL(widgetDeepLink)
    }

    private var classicSenderBubble: some View {
        let size: CGFloat = isSmall ? 22 : 28
        return ZStack {
            Circle().fill(Color.black.opacity(0.7))
            if let avatar = entry.senderAvatarImage {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(entry.senderFirstName.prefix(1).uppercased())
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
        }
    }

    private func disc(art: UIImage, diameter: CGFloat) -> some View {
        let r = diameter / 2

        return ZStack {
            Image(uiImage: art)
                .resizable()
                .scaledToFill()
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())

            discRing(radius: r * 0.992, width: max(0.7, r * 0.012), color: .black.opacity(0.42))
            discRing(radius: r * 0.967, width: max(0.6, r * 0.014), color: .white.opacity(0.28))
            discRing(radius: r * 0.303, width: max(0.6, r * 0.012), color: .black.opacity(0.22))
            discRing(radius: r * 0.218, width: max(0.5, r * 0.012), color: .black.opacity(0.28))
            discRing(radius: r * 0.225, width: max(0.5, r * 0.010), color: .white.opacity(0.22))
            discRing(radius: r * 0.175, width: max(0.8, r * 0.046), color: .white.opacity(0.20))
            discRing(radius: r * 0.156, width: max(0.5, r * 0.010), color: .black.opacity(0.20))

            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.26), location: 0),
                    .init(color: .white.opacity(0.05), location: 0.18),
                    .init(color: .clear, location: 0.38),
                    .init(color: .clear, location: 0.62),
                    .init(color: .white.opacity(0.04), location: 0.80),
                    .init(color: .white.opacity(0.16), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .opacity(0.42)
            .clipShape(Circle())
        }
        .frame(width: diameter, height: diameter)
        .compositingGroup()
        .mask {
            DiscDonut(holeRatio: Self.hubHoleRatio)
                .fill(style: FillStyle(eoFill: true))
        }
        .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
    }

    private func discRing(radius: CGFloat, width: CGFloat, color: Color) -> some View {
        Circle()
            .strokeBorder(color, lineWidth: width)
            .frame(width: radius * 2 + width, height: radius * 2 + width)
    }

    private var caseGlare: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.30),
                .init(color: .white.opacity(0.16), location: 0.41),
                .init(color: .clear, location: 0.49),
                .init(color: .clear, location: 0.70),
                .init(color: .white.opacity(0.10), location: 0.80),
                .init(color: .clear, location: 0.88),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blendMode(.screen)
        .opacity(0.7)
        .allowsHitTesting(false)
    }

    private var pillLabel: (text: String, isMessage: Bool) {
        let msg = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !msg.isEmpty { return (msg, true) }
        let name = entry.senderFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.count > Self.nameMax { return ("sent you a song", false) }
        return ("\(name) sent you a song", false)
    }

    private func senderPill(em: CGFloat) -> some View {
        let label = pillLabel
        let textSize = max(10, em)

        return HStack(spacing: em * 0.5) {
            pillAvatar(size: em * 2.15)
            Text(label.text)
                .font(.system(size: textSize, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(label.isMessage ? (isSmall ? 3 : 4) : 2)
                .minimumScaleFactor(label.isMessage ? 1 : 0.85)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            if !label.isMessage {
                Image(systemName: "heart.fill")
                    .font(.system(size: textSize * 0.85, weight: .semibold))
                    .foregroundStyle(Color(white: 0.82).opacity(0.55))
            }
        }
        .padding(.leading, em * 0.32)
        .padding(.trailing, em * 0.92)
        .padding(.vertical, em * 0.32)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color(red: 28 / 255, green: 28 / 255, blue: 32 / 255).opacity(0.46))
            }
        }
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pillAvatar(size: CGFloat) -> some View {
        ZStack {
            if let avatar = entry.senderAvatarImage {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 125 / 255, green: 133 / 255, blue: 144 / 255),
                        Color(red: 93 / 255, green: 100 / 255, blue: 110 / 255),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(entry.senderFirstName.prefix(1).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.2)
        }
        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
    }

    private var widgetDeepLink: URL? {
        if let id = entry.shareId, !id.isEmpty {
            return URL(string: "playme://share/\(id)")
        }
        return URL(string: "playme://")
    }
}

private struct DiscDonut: Shape {
    var holeRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: rect)
        let holeD = rect.width * holeRatio
        p.addEllipse(in: CGRect(
            x: rect.midX - holeD / 2,
            y: rect.midY - holeD / 2,
            width: holeD,
            height: holeD
        ))
        return p
    }
}

struct PlayMeWidget: Widget {
    let kind: String = "PlayMeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SongProvider()) { entry in
            PlayMeWidgetView(entry: entry)
                .id("\(entry.style.rawValue)-\(entry.styleEpoch)")
        }
        .configurationDisplayName("Play Me")
        .description("Latest song someone sent you, their note, and who sent it.")
        .supportedFamilies([.systemSmall])
        .containerBackgroundRemovable(false)
        .contentMarginsDisabled()
    }
}
