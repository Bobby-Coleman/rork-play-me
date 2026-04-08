import Foundation

enum MockData {
    static let songs: [Song] = [
        Song(id: "1", title: "Blinding Lights", artist: "The Weeknd", albumArtURL: "https://i.scdn.co/image/ab67616d0000b2738863bc11d2aa12b54f5aeb36", duration: "3:20"),
        Song(id: "2", title: "Whispers in the Pines", artist: "Luna & The Woods", albumArtURL: "https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=600&h=600&fit=crop", duration: "3:22"),
        Song(id: "3", title: "City Lights in the Rain", artist: "Neon Eclipse", albumArtURL: "https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=600&h=600&fit=crop", duration: "4:34"),
        Song(id: "4", title: "Moments & Motion", artist: "Jade Rivers", albumArtURL: "https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&h=600&fit=crop", duration: "3:48"),
        Song(id: "5", title: "Golden Hour", artist: "Mystic Source", albumArtURL: "https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=600&h=600&fit=crop", duration: "4:12"),
        Song(id: "6", title: "Midnight Drive", artist: "The Velvet Haze", albumArtURL: "https://images.unsplash.com/photo-1571330735066-03aaa9429d89?w=600&h=600&fit=crop", duration: "3:56"),
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
