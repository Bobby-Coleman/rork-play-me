import Foundation
import SpotifyiOS
import UIKit

class SpotifyPlaybackService: NSObject, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    static let shared = SpotifyPlaybackService()

    private(set) var isConnected: Bool = false
    private(set) var isPaused: Bool = true
    private(set) var currentTrackURI: String?
    private(set) var playbackPositionMs: Int = 0
    private(set) var trackDurationMs: UInt = 0
    private(set) var connectionError: String?

    var onStateChange: (() -> Void)?
    var pendingAuthCode: String?

    private var pendingPlayURI: String?
    private var requestedTrackURI: String?
    private var progressTimer: Timer?
    private var connectionRetryCount = 0
    private let maxConnectionRetries = 3

    private lazy var configuration: SPTConfiguration = {
        let clientID = Config.EXPO_PUBLIC_SPOTIFY_CLIENT_ID.isEmpty
            ? "10ac0a719f3e4135a2d3fd857c67d0f6"
            : Config.EXPO_PUBLIC_SPOTIFY_CLIENT_ID
        let redirectURL = URL(string: "playme://spotify-callback")!
        let config = SPTConfiguration(clientID: clientID, redirectURL: redirectURL)
        let base = Config.firebaseFunctionsBaseURL
        config.tokenSwapURL = URL(string: "\(base)/swap")!
        config.tokenRefreshURL = URL(string: "\(base)/refresh")!
        return config
    }()

    private lazy var appRemote: SPTAppRemote = {
        let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        remote.delegate = self
        return remote
    }()

    override init() {
        super.init()
    }

    func authorizeAndPlay() {
        appRemote.authorizeAndPlayURI("")
    }

    func authParameters(from url: URL) -> [String: String]? {
        return appRemote.authorizationParameters(from: url)
    }

    func connect() {
        connectionRetryCount = 0
        attemptConnect()
    }

    private func attemptConnect() {
        Task { @MainActor in
            guard let token = await SpotifyAuthService.shared.validToken(), !token.isEmpty else {
                connectionError = "No Spotify access token"
                onStateChange?()
                return
            }
            appRemote.connectionParameters.accessToken = token
            appRemote.connect()
        }
    }

    func connectWithToken(_ token: String) {
        connectionRetryCount = 0
        appRemote.connectionParameters.accessToken = token
        appRemote.connect()
    }

    func disconnect() {
        stopProgressTimer()
        if appRemote.isConnected {
            appRemote.disconnect()
        }
    }

    func play(uri: String) {
        guard appRemote.isConnected else {
            pendingPlayURI = uri
            connect()
            return
        }
        currentTrackURI = uri
        requestedTrackURI = uri
        appRemote.playerAPI?.play(uri, callback: { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.connectionError = error.localizedDescription
                    self.onStateChange?()
                } else {
                    self.isPaused = false
                    self.playbackPositionMs = 0
                    self.connectionError = nil
                    self.startProgressTimer()
                    self.onStateChange?()
                }
            }
        })
    }

    func pause() {
        appRemote.playerAPI?.pause({ [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if error == nil {
                    self.isPaused = true
                    self.stopProgressTimer()
                    self.onStateChange?()
                }
            }
        })
    }

    func resume() {
        appRemote.playerAPI?.resume({ [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if error == nil {
                    self.isPaused = false
                    self.startProgressTimer()
                    self.onStateChange?()
                }
            }
        })
    }

    func seek(toPositionMs positionMs: Int) {
        playbackPositionMs = positionMs
        appRemote.playerAPI?.seek(toPosition: positionMs, callback: { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.onStateChange?()
            }
        })
    }

    func getPlayerState() {
        appRemote.playerAPI?.getPlayerState({ [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, let state = result as? SPTAppRemotePlayerState else { return }
                self.updateFromPlayerState(state)
            }
        })
    }

    // MARK: - SPTAppRemoteDelegate

    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isConnected = true
            self.connectionError = nil
            self.connectionRetryCount = 0

            appRemote.playerAPI?.delegate = self
            appRemote.playerAPI?.subscribe(toPlayerState: { _, error in
                if let error {
                    print("SpotifyPlayback: subscribe error: \(error.localizedDescription)")
                }
            })

            if let uri = self.pendingPlayURI {
                self.pendingPlayURI = nil
                self.play(uri: uri)
            } else {
                appRemote.playerAPI?.pause(nil)
            }

            if let code = self.pendingAuthCode {
                self.pendingAuthCode = nil
                Task {
                    await SpotifyAuthService.shared.retrieveTokensFromServer(code: code)
                }
            }

            self.onStateChange?()
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isConnected = false
            self.stopProgressTimer()
            self.onStateChange?()
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isConnected = false

            if self.connectionRetryCount < self.maxConnectionRetries {
                self.connectionRetryCount += 1
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    self.attemptConnect()
                }
            } else {
                self.pendingPlayURI = nil
                self.connectionError = error?.localizedDescription ?? "Connection failed"
                self.onStateChange?()
            }
        }
    }

    // MARK: - SPTAppRemotePlayerStateDelegate

    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        Task { @MainActor [weak self] in
            self?.updateFromPlayerState(playerState)
        }
    }

    // MARK: - Internal

    private func updateFromPlayerState(_ state: SPTAppRemotePlayerState) {
        if let requested = requestedTrackURI,
           state.track.uri != requested,
           !state.isPaused {
            appRemote.playerAPI?.pause(nil)
            isPaused = true
            stopProgressTimer()
            requestedTrackURI = nil
            onStateChange?()
            return
        }

        isPaused = state.isPaused
        playbackPositionMs = state.playbackPosition
        trackDurationMs = state.track.duration
        currentTrackURI = state.track.uri

        if !isPaused {
            startProgressTimer()
        } else {
            stopProgressTimer()
        }

        onStateChange?()
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isPaused else { return }
                self.playbackPositionMs += 100
                self.onStateChange?()
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func openSpotifyToPlay(uri: String) {
        if let url = URL(string: uri) {
            UIApplication.shared.open(url)
        }
    }
}
