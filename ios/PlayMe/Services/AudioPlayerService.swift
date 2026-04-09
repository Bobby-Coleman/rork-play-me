import Foundation
import AVFoundation
import UIKit

@Observable
@MainActor
final class PlayerProgressModel {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    func formattedTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }

    func reset() {
        currentTime = 0
        duration = 0
    }
}

@Observable
@MainActor
class AudioPlayerService {
    static let shared = AudioPlayerService()

    var isPlaying: Bool = false
    var currentSongId: String?
    var isLoading: Bool = false
    var error: String?

    let progressModel = PlayerProgressModel()

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: (any NSObjectProtocol)?
    private var statusObservation: NSKeyValueObservation?

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
    }

    func play(song: Song) {
        if let previewURLString = song.previewURL, let url = URL(string: previewURLString) {
            playViaAVPlayer(url: url, song: song)
            return
        }

        error = "No preview available"
    }

    private func playViaAVPlayer(url: URL, song: Song) {
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
                    self.progressModel.duration = item.duration.seconds.isFinite ? item.duration.seconds : 30
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

    func seek(to time: TimeInterval) {
        progressModel.currentTime = time
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player?.pause()
        removeTimeObserver()
        removeEndObserver()
        statusObservation?.invalidate()
        statusObservation = nil
        player = nil
        isPlaying = false
        progressModel.reset()
        currentSongId = nil
        isLoading = false
        error = nil
    }

    private func addTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.progressModel.currentTime = seconds
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
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.progressModel.currentTime = 0
                self.player?.seek(to: .zero)
            }
        }
    }

    private func removeEndObserver() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
    }
}
