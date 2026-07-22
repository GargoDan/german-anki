import AVFoundation
import Foundation

/// Plays the bundled German audio. Files live in the blue-folder resource
/// "audio/words/word_*.m4a" and "audio/sentences/sent_*.m4a"; each clip is a
/// couple of seconds, so a fresh AVAudioPlayer per play is instant.
@Observable
final class AudioPlayer {
    private var player: AVAudioPlayer?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    func play(_ filename: String) {
        let subdirectory = filename.hasPrefix("word_") ? "words" : "sentences"
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("audio/\(subdirectory)/\(filename)"),
            FileManager.default.fileExists(atPath: url.path)
        else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
