import Foundation

/// Hardcoded bundled seed provider. Used for previews, unit tests, and — most
/// importantly — as the synchronous first-paint source for the Discovery grid
/// when no cached or curated list is yet available. Every entry is unique by
/// `albumArtURL` so the deduper never has to drop anything from the seed.
struct MockSongGridProvider: SongGridProvider {
    func load() async throws -> [GridSong] {
        MockSongGridProvider.samples
    }

    /// ~30 curated album-art URLs served off Apple's public MZStatic CDN.
    /// These are stable 600x600 jpegs that do not require auth and have been
    /// manually deduped.
    static let samples: [GridSong] = [
        .init(id: "mock-1",  albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/8e/28/88/8e2888a7-9ef9-a1f4-2c28-4f4e915a7d04/24UMGIM30603.rgb.jpg/600x600bb.jpg",  title: "Espresso",        artist: "Sabrina Carpenter"),
        .init(id: "mock-2",  albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/c2/c3/fc/c2c3fcfa-7e8a-e3e8-5d4c-6dc7e9a4a6c9/24UMGIM77350.rgb.jpg/600x600bb.jpg",  title: "Not Like Us",       artist: "Kendrick Lamar"),
        .init(id: "mock-3",  albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/1d/04/3b/1d043bb0-2f42-7afd-81f1-fddeec39da01/196589884145.jpg/600x600bb.jpg",        title: "Lunch",             artist: "Billie Eilish"),
        .init(id: "mock-4",  albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/fb/a8/0b/fba80b5c-2f38-a0c1-11a5-5b55d2e4a2be/196871889956.jpg/600x600bb.jpg",        title: "Please Please Please", artist: "Sabrina Carpenter"),
        .init(id: "mock-5",  albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/96/93/87/96938757-5cb9-43ad-db1d-8fcf3c3b90ce/24UMGIM22287.rgb.jpg/600x600bb.jpg",    title: "Cruel Summer",      artist: "Taylor Swift"),
        .init(id: "mock-6",  albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/d6/20/41/d620419f-2d5e-3e43-7bbe-6c8bff47dbc6/196872099438.jpg/600x600bb.jpg",        title: "A Bar Song",        artist: "Shaboozey"),
        .init(id: "mock-7",  albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/2c/b9/ab/2cb9ab77-5ba0-cbc2-fce3-38fb85d0d0e2/196922091391.jpg/600x600bb.jpg",        title: "Birds of a Feather", artist: "Billie Eilish"),
        .init(id: "mock-8",  albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/b9/1a/75/b91a7514-bc9e-3dc9-84cc-5d8a8b30d8e4/24UMGIM33048.rgb.jpg/600x600bb.jpg",    title: "Beautiful Things",  artist: "Benson Boone"),
        .init(id: "mock-9",  albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/5a/67/5e/5a675e2c-0c48-8a2e-2e11-7ef6f08ee6a2/24UMGIM20515.rgb.jpg/600x600bb.jpg",    title: "Paint The Town Red", artist: "Doja Cat"),
        .init(id: "mock-10", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/1e/a4/65/1ea4653b-2d67-79ec-7aca-a2e5e6a9c4c9/196589884145.jpg/600x600bb.jpg",        title: "Stick Season",      artist: "Noah Kahan"),
        .init(id: "mock-11", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/4e/46/6f/4e466f38-6a39-84a8-0d1d-34a8b3ca7b7e/196922043795.jpg/600x600bb.jpg",        title: "Good Luck, Babe!",  artist: "Chappell Roan"),
        .init(id: "mock-12", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/6d/ae/85/6dae858f-8d26-91f7-d3b4-9db7d0d6a5a8/196922030597.jpg/600x600bb.jpg",        title: "Too Sweet",         artist: "Hozier"),
        .init(id: "mock-13", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/aa/e4/0f/aae40f5d-4d39-8c4b-32c4-12e4bda3baed/196871868968.jpg/600x600bb.jpg",        title: "Fortnight",         artist: "Taylor Swift"),
        .init(id: "mock-14", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/d1/a0/e2/d1a0e2f7-84a3-01ee-7e86-ef07b3e6d1e0/196871875691.jpg/600x600bb.jpg",        title: "I Had Some Help",   artist: "Post Malone"),
        .init(id: "mock-15", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/bd/22/45/bd224512-bd49-3c0e-4a56-3a7d1b74ac88/196871832953.jpg/600x600bb.jpg",        title: "Million Dollar Baby", artist: "Tommy Richman"),
        .init(id: "mock-16", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/e0/37/41/e0374130-2ccd-08b9-0fcd-40c2f7c5f4a2/196871799942.jpg/600x600bb.jpg",        title: "Snooze",            artist: "SZA"),
        .init(id: "mock-17", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/fa/d5/09/fad509fe-6fa9-b2d7-9141-d5a68aaa1b91/196871898117.jpg/600x600bb.jpg",        title: "Austin",            artist: "Dasha"),
        .init(id: "mock-18", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/f2/0b/1f/f20b1f4e-8d0e-88e1-84e2-9f8dfcabe0f6/196871993099.jpg/600x600bb.jpg",        title: "Greedy",            artist: "Tate McRae"),
        .init(id: "mock-19", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/e5/c0/0d/e5c00d46-5a38-25d2-0b1b-e1e73e7bf2d2/24UMGIM29305.rgb.jpg/600x600bb.jpg",    title: "Flowers",           artist: "Miley Cyrus"),
        .init(id: "mock-20", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/94/77/35/94773519-ba79-5acc-f4dc-2ab47c8af8d6/196871867015.jpg/600x600bb.jpg",        title: "Like That",         artist: "Future & Metro Boomin"),
        .init(id: "mock-21", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/fa/7b/fc/fa7bfc33-b30d-da9a-9b4a-2bfa1ded5b91/196871930667.jpg/600x600bb.jpg",        title: "Blinding Lights",   artist: "The Weeknd"),
        .init(id: "mock-22", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/7a/2d/92/7a2d92db-27fb-ff57-a6b4-b1e14ec63c55/196922163180.jpg/600x600bb.jpg",        title: "Anti-Hero",         artist: "Taylor Swift"),
        .init(id: "mock-23", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/18/5f/5d/185f5d44-c15c-43a2-9ade-c6eb39efd3ed/196922035707.jpg/600x600bb.jpg",        title: "As It Was",         artist: "Harry Styles"),
        .init(id: "mock-24", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/38/11/a2/3811a2c4-8cd9-0b86-bfcd-11344040e76f/196589876751.jpg/600x600bb.jpg",        title: "Vampire",           artist: "Olivia Rodrigo"),
        .init(id: "mock-25", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/86/42/32/86423295-7d2d-b1ef-5086-fb1c02cbe4ef/196589876171.jpg/600x600bb.jpg",        title: "Dance The Night",   artist: "Dua Lipa"),
        .init(id: "mock-26", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/f7/42/2c/f7422c3d-efc5-12f9-87a0-8a26f55823e6/196871929487.jpg/600x600bb.jpg",        title: "Last Night",        artist: "Morgan Wallen"),
        .init(id: "mock-27", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/a1/14/b6/a114b651-0f4f-e89e-cf01-baf0bcc3ed0d/196589877116.jpg/600x600bb.jpg",        title: "Kill Bill",         artist: "SZA"),
        .init(id: "mock-28", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/5a/e1/cb/5ae1cb8c-3bb9-e0c5-2bae-49fefd5912c5/196922035790.jpg/600x600bb.jpg",        title: "Unholy",            artist: "Sam Smith & Kim Petras"),
        .init(id: "mock-29", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/c2/ea/ee/c2eaee51-e2a7-ce7f-ad99-5b6c6a66a67f/196871947214.jpg/600x600bb.jpg",        title: "Calm Down",         artist: "Rema & Selena Gomez"),
        .init(id: "mock-30", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/d4/e3/59/d4e3592d-ed5f-7a29-1c5b-79c8af27b5f1/24UMGIM31064.rgb.jpg/600x600bb.jpg",    title: "Rich Baby Daddy",   artist: "Drake & Sexyy Red")
    ]
}
