//VideoPlayerView.Swift
import SwiftUI
import AVKit

/// Minimal AVPlayerView wrapper that renders *only* the video (no built-in controls),
/// so overlays align perfectly with the visible pixels.
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .none                 // no transport bar/chrome
        v.showsFullScreenToggleButton = false
        v.allowsPictureInPicturePlayback = false
        v.videoGravity = .resizeAspect          // fit inside bounds; matches our aspect math
        v.player = player
        return v
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
