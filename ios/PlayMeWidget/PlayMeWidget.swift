import WidgetKit
import SwiftUI

private let widgetAppGroupId = "group.app.rork.playme.shared"

nonisolated struct SongEntry: TimelineEntry {
    let date: Date
    let songTitle: String
    let songArtist: String
    let albumImage: UIImage?
    let senderFirstName: String
    let note: String?
    let shareId: String?
}

nonisolated struct SongProvider: TimelineProvider {
    func placeholder(in context: Context) -> SongEntry {
        SongEntry(
            date: .now,
            songTitle: "Can't Help Myself",
            songArtist: "Kita Alexander",
            albumImage: nil,
            senderFirstName: "Molly",
            note: "this song reminds me of you",
            shareId: nil
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
        let title = defaults?.string(forKey: "widgetSongTitle") ?? "Play Me"
        let artist = defaults?.string(forKey: "widgetSongArtist") ?? "Open the app to see songs"
        let firstName = defaults?.string(forKey: "widgetSenderFirstName") ?? ""
        let note = defaults?.string(forKey: "widgetNote")
        let shareId = defaults?.string(forKey: "widgetShareId")

        var albumImage: UIImage? = nil
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: widgetAppGroupId) {
            let imageFile = containerURL.appendingPathComponent("widgetAlbumArt.jpg")
            albumImage = UIImage(contentsOfFile: imageFile.path)
        }

        return SongEntry(
            date: .now,
            songTitle: title,
            songArtist: artist,
            albumImage: albumImage,
            senderFirstName: firstName,
            note: note,
            shareId: shareId
        )
    }
}

struct PlayMeWidgetView: View {
    var entry: SongEntry
    @Environment(\.widgetFamily) var family

    private var isSmall: Bool { family == .systemSmall }

    private var noteSize: CGFloat { isSmall ? 10 : 12 }
    private var noteLineLimit: Int { isSmall ? 4 : 6 }
    private var bubbleSize: CGFloat { isSmall ? 22 : 28 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear

            if !entry.senderFirstName.isEmpty || (entry.note != nil && !(entry.note!.isEmpty)) {
                HStack(alignment: .bottom, spacing: 5) {
                    if !entry.senderFirstName.isEmpty {
                        senderBubble
                    }

                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: noteSize, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(noteLineLimit)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 2)
                .padding(.trailing, 2)
                .padding(.bottom, 0)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .containerBackground(for: .widget) {
            fullBleedAlbumBackground
        }
        .widgetURL(widgetDeepLink)
    }

    private var widgetDeepLink: URL? {
        if let id = entry.shareId, !id.isEmpty {
            return URL(string: "playme://share/\(id)")
        }
        return URL(string: "playme://")
    }

    @ViewBuilder
    private var fullBleedAlbumBackground: some View {
        if let uiImage = entry.albumImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Color(white: 0.08)
        }
    }

    private var senderBubble: some View {
        Text(entry.senderFirstName.prefix(1).uppercased())
            .font(.system(size: bubbleSize * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: bubbleSize, height: bubbleSize)
            .background(Color.black.opacity(0.7))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            }
    }
}

struct PlayMeWidget: Widget {
    let kind: String = "PlayMeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SongProvider()) { entry in
            PlayMeWidgetView(entry: entry)
        }
        .configurationDisplayName("Play Me")
        .description("Latest song someone sent you, their note, and who sent it.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .containerBackgroundRemovable(false)
    }
}
