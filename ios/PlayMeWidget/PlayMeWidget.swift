import WidgetKit
import SwiftUI

nonisolated struct SongEntry: TimelineEntry {
    let date: Date
    let songTitle: String
    let songArtist: String
    let albumArtURL: String
    let senderInitials: String
    let note: String?
    let shareId: String?
}

nonisolated struct SongProvider: TimelineProvider {
    func placeholder(in context: Context) -> SongEntry {
        SongEntry(
            date: .now,
            songTitle: "Can't Help Myself",
            songArtist: "Kita Alexander",
            albumArtURL: "https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=600&h=600&fit=crop",
            senderInitials: "MJ",
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
        let defaults = UserDefaults(suiteName: "group.app.rork.playme.shared")
        let title = defaults?.string(forKey: "widgetSongTitle") ?? "Play Me"
        let artist = defaults?.string(forKey: "widgetSongArtist") ?? "Send a song to get started"
        let artURL = defaults?.string(forKey: "widgetAlbumArtURL") ?? ""
        let initials = defaults?.string(forKey: "widgetSenderInitials") ?? ""
        let note = defaults?.string(forKey: "widgetNote")
        let shareId = defaults?.string(forKey: "widgetShareId")

        return SongEntry(
            date: .now,
            songTitle: title,
            songArtist: artist,
            albumArtURL: artURL,
            senderInitials: initials,
            note: note,
            shareId: shareId
        )
    }
}

struct PlayMeWidgetView: View {
    var entry: SongEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            if !entry.albumArtURL.isEmpty, let url = URL(string: entry.albumArtURL) {
                Color.black
                    .overlay {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.7), .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Color.black
            }

            VStack(alignment: .leading, spacing: 0) {
                if !entry.senderInitials.isEmpty {
                    Text(entry.senderInitials)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.25))
                        .clipShape(Circle())
                }

                Spacer()

                Text(entry.songTitle)
                    .font(.system(size: family == .systemSmall ? 13 : 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(entry.songArtist)
                    .font(.system(size: family == .systemSmall ? 10 : 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: family == .systemSmall ? 9 : 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(.black, for: .widget)
        .widgetURL(URL(string: "playme://share/\(entry.shareId ?? "")"))
    }
}

struct PlayMeWidget: Widget {
    let kind: String = "PlayMeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SongProvider()) { entry in
            PlayMeWidgetView(entry: entry)
        }
        .configurationDisplayName("Play Me")
        .description("See the latest song sent to you.")
        .supportedFamilies([.systemSmall])
        .containerBackgroundRemovable(false)
    }
}
