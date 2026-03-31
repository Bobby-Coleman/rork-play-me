import Foundation
import AVFoundation
import UIKit

@Observable
@MainActor
class AudioPlayerService {
    static let shared = AudioPlayerService()

    var isPlaying: Bool = false
    var currentSongId: String?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isLoading: Bool = false
    var error: String?
    var noPreviewAvailable: Bool = false
    var isUsingSpotify: Bool = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?

    private var currentSpotifyURI: String?
    private let spotifyPlayback = SpotifyPlaybackService.shared

    private init() {
        setupAudioSession()
        setupSpotifyCallbacks()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
    }

    private func setupSpotifyCallbacks() {
        spotifyPlayback.onStateChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncFromSpotifyState()
            }
        }
    }

    func play(song: Song) {
        if let spotifyURI = song.spotifyURI, !spotifyURI.isEmpty {
            playViaSpotify(uri: spotifyURI, song: song)
            return
        }

        if let previewURLString = song.previewURL, let url = URL(string: previewURLString) {
            playViaAVPlayer(url: url, song: song)
            return
        }

        noPreviewAvailable = true
        error = "No preview available — open in Spotify to listen"
    }

    // MARK: - Spotify Playback

    private func playViaSpotify(uri: String, song: Song) {
        noPreviewAvailable = false

        if currentSongId == song.id && isUsingSpotify {
            if isPlaying {
                spotifyPlayback.pause()
            } else {
                spotifyPlayback.resume()
            }
            return
        }

        stopAVPlayer()
        isUsingSpotify = true
        isLoading = true
        error = nil
        currentSongId = song.id
        currentSpotifyURI = uri
        currentTime = 0

        let durationParts = song.duration.split(separator: ":")
        if durationParts.count == 2,
           let mins = Double(durationParts[0]),
           let secs = Double(durationParts[1]) {
            duration = mins * 60 + secs
        } else {
            duration = 0
        }

        spotifyPlayback.play(uri: uri)
    }

    private func syncFromSpotifyState() {
        guard isUsingSpotify else { return }

        let pb = spotifyPlayback

        if pb.isConnected && !pb.isPaused {
            isLoading = false
            isPlaying = true
        } else if pb.isConnected && pb.isPaused {
            isLoading = false
            isPlaying = false
        }

        if pb.trackDurationMs > 0 {
            duration = Double(pb.trackDurationMs) / 1000.0
        }
        currentTime = Double(pb.playbackPositionMs) / 1000.0

        if let err = pb.connectionError {
            isLoading = false
            error = err
        }
    }

    // MARK: - AVPlayer Playback (fallback for preview URLs)

    private func playViaAVPlayer(url: URL, song: Song) {
        noPreviewAvailable = false

        if currentSongId == song.id && !isUsingSpotify, let player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            return
        }

        stop()
        isUsingSpotify = false
        isLoading = true
        error = nil
        currentSongId = song.id

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        statusObservation = playerItem.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 30
                    self.player?.play()
                    self.isPlaying = true
                case .failed:
                    self.isLoading = false
                    self.error = "Failed to load audio"
                    self.isPlaying = false
                default:
                    break
                }
            }
        }

        addTimeObserver()
        addEndObserver()
    }

    // MARK: - Public Controls

    func togglePlayPause() {
        if isUsingSpotify {
            if isPlaying {
                spotifyPlayback.pause()
            } else {
                spotifyPlayback.resume()
            }
        } else if let player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
        }
    }

    func seek(to time: TimeInterval) {
        currentTime = time
        if isUsingSpotify {
            spotifyPlayback.seek(toPositionMs: Int(time * 1000))
        } else {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func stop() {
        if isUsingSpotify {
            spotifyPlayback.pause()
        }
        stopAVPlayer()
        isUsingSpotify = false
        isPlaying = false
        currentTime = 0
        duration = 0
        currentSongId = nil
        currentSpotifyURI = nil
        isLoading = false
        error = nil
        noPreviewAvailable = false
    }

    private func stopAVPlayer() {
        player?.pause()
        removeTimeObserver()
        statusObservation?.invalidate()
        statusObservation = nil
        durationObservation = nil
        player = nil
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - AVPlayer Observers

    private func addTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isUsingSpotify else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = seconds
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func addEndObserver() {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = 0
                self.player?.seek(to: .zero)
            }
        }
    }

    func formattedTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
