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

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
    }

    var noPreviewAvailable: Bool = false

    func play(song: Song) {
        guard let previewURLString = song.previewURL,
              let url = URL(string: previewURLString) else {
            noPreviewAvailable = true
            error = "No preview available — open in Spotify to listen"
            return
        }
        noPreviewAvailable = false

        if currentSongId == song.id, let player {
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

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func stop() {
        player?.pause()
        removeTimeObserver()
        statusObservation?.invalidate()
        statusObservation = nil
        durationObservation = nil
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentSongId = nil
        isLoading = false
        error = nil
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    private func addTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
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

    private func openInSpotify(uri: String) {
        if let url = URL(string: uri) {
            UIApplication.shared.open(url)
        }
    }

    func formattedTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
