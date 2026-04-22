import Foundation

/// Hardcoded bundled seed provider. Used for previews, unit tests, and — most
/// importantly — as the synchronous first-paint source for the Discovery grid
/// when no cached or curated list is yet available.
///
/// Every entry here was harvested from the public iTunes Search API and its
/// 600x600 artwork URL was verified to return HTTP 200 against the MZStatic
/// CDN. That matters: earlier seeds were hand-assembled and resolved to 404s,
/// which rendered an empty grid. Regenerate the list by re-running iTunes
/// Search + HEAD-check when refreshing the rotation.
struct MockSongGridProvider: SongGridProvider {
    func load() async throws -> [GridSong] {
        MockSongGridProvider.samples
    }

    static let samples: [GridSong] = [
        .init(id: "itunes-1440829630", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/51/61/f3/5161f3c4-2292-f035-eb68-6f95bbc9edd6/00602537542338.rgb.jpg/600x600bb.jpg",      title: "Hold On, We're Going Home", artist: "Drake"),
        .init(id: "itunes-1662168786", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music123/v4/09/aa/f8/09aaf8da-8eaf-bf60-0c23-48a88d546cbd/26991.jpg/600x600bb.jpg",                    title: "MIA",                        artist: "Bad Bunny"),
        .init(id: "itunes-1440843496", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/95/f5/87/95f587f7-21c3-d5f9-d81a-4350f9caa020/16UMGIM27643.rgb.jpg/600x600bb.jpg",          title: "One Dance",                  artist: "Drake"),
        .init(id: "itunes-1447555315", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/cf/3a/db/cf3adbe6-8ea1-f60f-60fd-713eefda3962/193483317984.jpg/600x600bb.jpg",              title: "MÍA",                        artist: "Bad Bunny"),
        .init(id: "itunes-1440841730", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/f2/0d/8b/f20d8bff-a927-ae98-6784-20a1f51cb23e/16UMGIM27642.rgb.jpg/600x600bb.jpg",          title: "Hotline Bling",              artist: "Drake"),
        .init(id: "itunes-1572737688", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/e7/ba/c3/e7bac380-e05a-5942-e576-cf426e4c41f2/21UMGIM55277.rgb.jpg/600x600bb.jpg",          title: "Drake",                      artist: "Still Woozy"),
        .init(id: "itunes-1833328840", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/2d/46/e0/2d46e0bc-8ab9-85dd-4b56-ee6951351034/25UM1IM19577.rgb.jpg/600x600bb.jpg",          title: "The Fate of Ophelia",        artist: "Taylor Swift"),
        .init(id: "itunes-1440936016", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/89/4a/4a/894a4ab9-b0b0-9ea5-ca41-8da0b9b79453/14UMDIM03405.rgb.jpg/600x600bb.jpg",          title: "Shake It Off",               artist: "Taylor Swift"),
        .init(id: "itunes-1468058171", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/49/3d/ab/493dab54-f920-9043-6181-80993b8116c9/19UMGIM53909.rgb.jpg/600x600bb.jpg",          title: "Cruel Summer",               artist: "Taylor Swift"),
        .init(id: "itunes-1452859427", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/59/dc/cb/59dccbb0-73f9-701e-7b5b-58c902ddfe68/09UMDIM00338.rgb.jpg/600x600bb.jpg",          title: "You Belong With Me",         artist: "Taylor Swift"),
        .init(id: "itunes-1739659144", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/92/9f/69/929f69f1-9977-3a44-d674-11f70c852d1b/24UMGIM36186.rgb.jpg/600x600bb.jpg",          title: "WILDFLOWER",                 artist: "Billie Eilish"),
        .init(id: "itunes-1440899467", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/02/1d/30/021d3036-5503-3ed3-df00-882f2833a6ae/17UM1IM17026.rgb.jpg/600x600bb.jpg",          title: "ocean eyes",                 artist: "Billie Eilish"),
        .init(id: "itunes-1369380479", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/27/94/d4/2794d4fc-c3e2-2373-3e6c-dd82fd5aefe6/18UMGIM18200.rgb.jpg/600x600bb.jpg",          title: "lovely",                     artist: "Billie Eilish & Khalid"),
        .init(id: "itunes-1450695739", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/1a/37/d1/1a37d1b1-8508-54f2-f541-bf4e437dda76/19UMGIM05028.rgb.jpg/600x600bb.jpg",          title: "bad guy",                    artist: "Billie Eilish"),
        .init(id: "itunes-1696819855", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/7d/64/76/7d64761e-a9b3-6754-8ae1-b457338beead/23UMGIM77779.rgb.jpg/600x600bb.jpg",          title: "What Was I Made For?",       artist: "Billie Eilish"),
        .init(id: "itunes-1781270323", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/50/c2/cc/50c2cc95-3658-9417-0d4b-831abde44ba1/24UM1IM28978.rgb.jpg/600x600bb.jpg",          title: "luther",                     artist: "Kendrick Lamar"),
        .init(id: "itunes-1440881708", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/86/c9/bb/86c9bb30-fe3d-442e-33c1-c106c4d23705/17UMGIM88776.rgb.jpg/600x600bb.jpg",          title: "LOVE.",                      artist: "Kendrick Lamar"),
        .init(id: "itunes-1781353929", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/31/3a/3f/313a3fbc-bb8f-80c7-b5a2-e226869a38cd/24UMGIM51924.rgb.jpg/600x600bb.jpg",          title: "Not Like Us",                artist: "Kendrick Lamar"),
        .init(id: "itunes-1781316952", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/54/28/14/54281424-eece-0935-299d-fdd2ab403f92/24UM1IM28978.rgb.jpg/600x600bb.jpg",          title: "tv off",                     artist: "Kendrick Lamar"),
        .init(id: "itunes-1440882165", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/ab/16/ef/ab16efe9-e7f1-66ec-021c-5592a23f0f9e/17UMGIM88793.rgb.jpg/600x600bb.jpg",          title: "HUMBLE.",                    artist: "Kendrick Lamar"),
        .init(id: "itunes-1787022572", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/90/5e/7e/905e7ed5-a8fa-a8f3-cd06-0028fdf3afaa/199066342442.jpg/600x600bb.jpg",              title: "NUEVAYoL",                   artist: "Bad Bunny"),
        .init(id: "itunes-1470146813", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/77/32/74/7732746d-25e5-baae-b921-bad4a07d87b1/19UMGIM55524.rgb.jpg/600x600bb.jpg",          title: "LA CANCIÓN",                 artist: "J Balvin & Bad Bunny"),
        .init(id: "itunes-1622045962", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/3e/04/eb/3e04ebf6-370f-f59d-ec84-2c2643db92f1/196626945068.jpg/600x600bb.jpg",              title: "Ojitos Lindos",              artist: "Bad Bunny"),
        .init(id: "itunes-1652080289", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music122/v4/4f/64/d2/4f64d264-ce5b-64a7-3d11-5d7550613db1/22UM1IM25832.rgb.jpg/600x600bb.jpg",          title: "No Me Conoce (Remix)",       artist: "JHAYCO, J Balvin & Bad Bunny"),
        .init(id: "itunes-1682500319", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/b6/74/4d/b6744dbd-77ed-413a-3777-5ac6a2e780eb/197188732554.jpg/600x600bb.jpg",              title: "un x100to",                  artist: "Grupo Frontera & Bad Bunny"),
        .init(id: "itunes-1732348414", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/0f/90/a8/0f90a856-0447-d846-fa7b-b9c937e72310/196871881180.jpg/600x600bb.jpg",              title: "Saturn",                     artist: "SZA"),
        .init(id: "itunes-1657869393", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music122/v4/bd/3b/a9/bd3ba9fb-9609-144f-bcfe-ead67b5f6ab3/196589564931.jpg/600x600bb.jpg",              title: "Kill Bill",                  artist: "SZA"),
        .init(id: "itunes-852343743",  albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/d8/86/70/d8867099-c280-065b-8617-53096e63fd55/859712300362_cover.jpg/600x600bb.jpg",       title: "Childs Play",                artist: "SZA"),
        .init(id: "itunes-1396141904", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/8a/49/80/8a49806e-e9b6-1025-f4a8-cf51edb4504b/17UM1IM31406.rgb.jpg/600x600bb.jpg",          title: "What Lovers Do",             artist: "Maroon 5"),
        .init(id: "itunes-1538003843", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/6c/11/d6/6c11d681-aa3a-d59e-4c2e-f77e181026ab/190295092665.jpg/600x600bb.jpg",              title: "Levitating",                 artist: "Dua Lipa"),
        .init(id: "itunes-1228739609", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/c1/54/2d/c1542d45-c6c2-12ca-7308-6eacd762c562/190295807870.jpg/600x600bb.jpg",              title: "New Rules",                  artist: "Dua Lipa"),
        .init(id: "itunes-1689238922", albumArtURL: "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/c0/54/97/c05497aa-c19f-bf4f-de29-71edf30fbefb/075679688767.jpg/600x600bb.jpg",              title: "Dance The Night",            artist: "Dua Lipa")
    ]
}
