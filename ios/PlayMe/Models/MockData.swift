import Foundation

enum MockData {
    static let songs: [Song] = [
        Song(id: "1", title: "Blinding Lights", artist: "The Weeknd", albumArtURL: "https://i.scdn.co/image/ab67616d0000b2738863bc11d2aa12b54f5aeb36", duration: "3:20", spotifyURI: "spotify:track:0VjIjW4GlUZAMYd2vXMi3b"),
        Song(id: "2", title: "Whispers in the Pines", artist: "Luna & The Woods", albumArtURL: "https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=600&h=600&fit=crop", duration: "3:22"),
        Song(id: "3", title: "City Lights in the Rain", artist: "Neon Eclipse", albumArtURL: "https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=600&h=600&fit=crop", duration: "4:34"),
        Song(id: "4", title: "Moments & Motion", artist: "Jade Rivers", albumArtURL: "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&h=600&fit=crop", duration: "3:48"),
        Song(id: "5", title: "Golden Hour", artist: "Mystic Source", albumArtURL: "https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=600&h=600&fit=crop", duration: "4:12"),
        Song(id: "6", title: "Midnight Drive", artist: "The Velvet Haze", albumArtURL: "https://images.unsplash.com/photo-1571330735066-03aaa9429d89?w=600&h=600&fit=crop", duration: "3:56"),
        Song(id: "7", title: "Bloom", artist: "Pale Winter", albumArtURL: "https://images.unsplash.com/photo-1484755560615-a4c64e778a6c?w=600&h=600&fit=crop", duration: "3:30"),
        Song(id: "8", title: "Echoes of You", artist: "Dream Coast", albumArtURL: "https://images.unsplash.com/photo-1506157786151-b8491531f063?w=600&h=600&fit=crop", duration: "4:05"),
        Song(id: "9", title: "Slow Burn", artist: "Amber Skies", albumArtURL: "https://images.unsplash.com/photo-1446057032654-9d8885db76c6?w=600&h=600&fit=crop", duration: "3:42"),
        Song(id: "10", title: "Neon Dreams", artist: "Glass Animals Jr.", albumArtURL: "https://images.unsplash.com/photo-1504898770365-14faca6a7320?w=600&h=600&fit=crop", duration: "4:18"),
        Song(id: "11", title: "Paper Planes", artist: "Wild Nothing", albumArtURL: "https://images.unsplash.com/photo-1485579149621-3123dd979885?w=600&h=600&fit=crop", duration: "3:10"),
        Song(id: "12", title: "Coastline", artist: "Tidal Wave", albumArtURL: "https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?w=600&h=600&fit=crop", duration: "3:55"),
        Song(id: "13", title: "After Dark", artist: "Noir Collective", albumArtURL: "https://images.unsplash.com/photo-1415201364774-f6f0bb35f28f?w=600&h=600&fit=crop", duration: "4:25"),
        Song(id: "14", title: "Satellite", artist: "Cosmic Drift", albumArtURL: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=600&h=600&fit=crop", duration: "3:38"),
        Song(id: "15", title: "Honey", artist: "Still Corners", albumArtURL: "https://images.unsplash.com/photo-1453090927415-5f45085b65c0?w=600&h=600&fit=crop", duration: "4:01"),
    ]

    static let friends: [AppUser] = [
        AppUser(id: "f1", firstName: "Molly", username: "mollyj", phone: ""),
        AppUser(id: "f2", firstName: "Alice", username: "alicegreen", phone: ""),
        AppUser(id: "f3", firstName: "Ben", username: "bencarter", phone: ""),
        AppUser(id: "f4", firstName: "Chloe", username: "chloedavis", phone: ""),
        AppUser(id: "f5", firstName: "David", username: "davidlee", phone: ""),
    ]

    static let currentUser = AppUser(id: "me", firstName: "Bobby", username: "bobbyc", phone: "")
}
