import SwiftUI
import FirebaseCore

@main
struct PlayMeApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
