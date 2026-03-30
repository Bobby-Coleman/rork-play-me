import Foundation
import AVFoundation
import UIKit

@Observable
@MainActor
class AudioPlayerService {
    static let shared = AudioPlayerService()

    var currentSong: Song?
    var isPlaying: Bool = false
    var progress: Double = 0
    var duration: Double = 0
    var isLoading: Bool = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init() {
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
    }

    func play(song: Song) {
        guard let urlString = song.previewURL, let url = URL(string: urlString) else {
            openInSpotify(song: song)
            return
        }

        if currentSong?.id == song.id {
            togglePlayPause()
            return
        }

        stop()
        currentSong = song
        isLoading = true

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        addTimeObserver()
        addEndObserver()

        player?.play()
        isPlaying = true
        isLoading = false
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func stop() {
        removeTimeObserver()
        removeEndObserver()
        player?.pause()
        player = nil
        isPlaying = false
        progress = 0
        duration = 0
        currentSong = nil
    }

    func seek(to fraction: Double) {
        guard let player, duration > 0 else { return }
        let time = CMTime(seconds: fraction * duration, preferredTimescale: 600)
        player.seek(to: time)
    }

    func openInSpotify(song: Song) {
        if let deepLink = song.spotifyDeepLink,
           UIApplication.shared.canOpenURL(deepLink) {
            UIApplication.shared.open(deepLink)
        } else if let webURL = song.spotifyWebURL {
            UIApplication.shared.open(webURL)
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, let item = self.player?.currentItem else { return }
                let dur = CMTimeGetSeconds(item.duration)
                let cur = CMTimeGetSeconds(time)
                if dur.isFinite && dur > 0 {
                    self.duration = dur
                    self.progress = cur / dur
                }
            }
        }
    }

    private func addEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.progress = 0
                self?.player?.seek(to: .zero)
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func removeEndObserver() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
    }
}
