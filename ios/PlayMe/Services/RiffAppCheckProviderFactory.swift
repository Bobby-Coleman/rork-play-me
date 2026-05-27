import Foundation
import FirebaseAppCheck
import FirebaseCore

/// Chooses the right Firebase App Check provider for each runtime.
///
/// - Debug builds use the debug provider so simulator/local development stays
///   usable while App Check is in monitor mode.
/// - Release builds on real iOS 14+ devices use App Attest, Apple's preferred
///   modern attestation provider.
/// - Older release devices fall back to DeviceCheck.
final class RiffAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        #if targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        }
        return DeviceCheckProvider(app: app)
        #endif
        #endif
    }
}
