import AVFoundation
import Combine
import Foundation
import ShazamKit

/// Foreground-only Shazam tag-to-search. Thin state-machine adapter around
/// `SHManagedSession` (iOS 17+), which owns the audio capture, signature
/// generation, and audio-session lifecycle that the older
/// `SHSession + AVAudioEngine` path required.
///
/// State machine:
///   `.idle` → `.preparing` (mic permission + `session.prepare()`)
///   → `.listening` → `.matched(Match)` | `.noMatch` | `.error(String)`
///
/// Why `SHManagedSession` instead of `SHSession` + `AVAudioEngine`?
/// Hand-rolling the tap with `AVAudioConverter` produced sub-buffer
/// discontinuities and required `.measurement` audio-session mode (no
/// AGC), both of which suppressed catalog matches on quiet rooms. The
/// managed path is Apple's documented modern API and handles all of it
/// internally.
///
/// Requires:
///   * `NSMicrophoneUsageDescription` in `Info.plist`.
///   * "ShazamKit" ticked under App Services for the App ID on
///     developer.apple.com — otherwise the catalog endpoint returns
///     HTTP 401 wrapped as `com.apple.ShazamKit Code=202`.
@MainActor
final class ShazamMatchService: ObservableObject {

    enum State: Equatable {
        case idle
        case preparing
        case listening
        case matched(Match)
        case noMatch
        case error(String)
    }

    struct Match: Equatable {
        let appleMusicID: String?
        let isrc: String?
        let title: String
        let artist: String
    }

    @Published private(set) var state: State = .idle

    private var session: SHManagedSession?
    private var resultTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    /// Belt-and-braces upper bound. `SHManagedSession.result()` normally
    /// returns a `.match` or `.noMatch` within a few seconds, so this
    /// only catches a genuine stall (e.g. the framework deadlocking on
    /// an audio-route change). Long enough that a real song still has
    /// time to fingerprint over a quiet room.
    private let listenTimeout: TimeInterval = 15

    // MARK: - Public API

    func start() async {
        if case .listening = state { return }
        if case .preparing = state { return }

        state = .preparing

        let granted = await requestMicPermission()
        guard granted else {
            state = .error("Microphone access is off. Enable it in Settings to use Shazam.")
            return
        }

        cancelInFlight()

        let session = SHManagedSession()
        self.session = session

        #if DEBUG
        print("[Shazam] preparing managed session")
        #endif
        await session.prepare()

        // The caller may have invoked `stop()` while `prepare()` was
        // awaiting; if so, don't transition into `.listening` and don't
        // start the result task — `cancelInFlight()` already tore the
        // session down.
        guard case .preparing = state else { return }

        state = .listening
        startTimeout()

        resultTask = Task { [weak self] in
            let result = await session.result()
            await self?.handleResult(result)
        }
    }

    /// Stops listening without changing terminal states. Used by
    /// lifecycle callers (scene phase, view disappearance) so the UI can
    /// keep showing the last `.matched`/`.noMatch`/`.error` result.
    func stop() {
        cancelInFlight()
        switch state {
        case .preparing, .listening:
            state = .idle
        default:
            break
        }
    }

    /// Returns to `.idle`. Use after the host UI consumes a terminal result.
    func reset() {
        cancelInFlight()
        state = .idle
    }

    // MARK: - Internals

    private func cancelInFlight() {
        timeoutTask?.cancel()
        timeoutTask = nil
        resultTask?.cancel()
        resultTask = nil
        session?.cancel()
        session = nil
    }

    private func requestMicPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        let deadline = listenTimeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadline))
            guard let self else { return }
            await MainActor.run {
                guard case .listening = self.state else { return }
                #if DEBUG
                print("[Shazam] local watchdog timeout — no result from SHManagedSession")
                #endif
                self.cancelInFlight()
                self.state = .noMatch
            }
        }
    }

    private func handleResult(_ result: SHSession.Result) async {
        // If the host already moved us out of `.listening` (cancel, stop,
        // or reset between `result()` returning and this hop to the main
        // actor), drop the result on the floor — the in-flight session
        // is already torn down.
        guard case .listening = state else {
            timeoutTask?.cancel()
            timeoutTask = nil
            session = nil
            resultTask = nil
            return
        }

        timeoutTask?.cancel()
        timeoutTask = nil
        session = nil
        resultTask = nil

        switch result {
        case .match(let match):
            guard let item = match.mediaItems.first else {
                #if DEBUG
                print("[Shazam] match returned 0 media items — surfacing as noMatch")
                #endif
                state = .noMatch
                return
            }
            #if DEBUG
            print("[Shazam] match: \(item.title ?? "?") — \(item.artist ?? "?") amID=\(item.appleMusicID ?? "nil") isrc=\(item.isrc ?? "nil")")
            #endif
            state = .matched(Match(
                appleMusicID: item.appleMusicID,
                isrc: item.isrc,
                title: item.title ?? "",
                artist: item.artist ?? ""
            ))

        case .noMatch:
            #if DEBUG
            print("[Shazam] noMatch")
            #endif
            state = .noMatch

        case .error(let error, _):
            let ns = error as NSError
            #if DEBUG
            print("[Shazam] error domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
            if ns.code == 202 {
                print("[Shazam] Code=202: ShazamKit App Service may not be enabled for this App ID on developer.apple.com.")
            }
            #endif
            state = .error(ns.localizedDescription)

        @unknown default:
            state = .error("Couldn't recognize the song.")
        }
    }
}
