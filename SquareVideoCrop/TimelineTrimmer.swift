//TimelinTrimmer.swift
import SwiftUI
import AVFoundation

struct TimelineTrimmer: View {
    let asset: AVAsset
    @Binding var start: Double
    @Binding var end: Double
    @Binding var playhead: Double
    
    // Transport control callbacks
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onSeek: ((Double) -> Void)?  // Called when skip buttons are used
    var isPlaying: Bool = false
    var onLoopChanged: ((Bool) -> Void)?  // Notify parent of loop state changes

    // Layout
    private let stripHeight: CGFloat = 64          // visible thumbnail strip
    private let handleW: CGFloat = 10              // trim handle visual width
    private let handleHitW: CGFloat = 10           // horizontal hit radius for handles (for picking mode) - matches visual width

    @State private var thumbs: [NSImage] = []
    @State private var dur: Double = 0
    @State private var loopEnabled: Bool = false
    @State private var fps: Double = 30.0  // Default to 30fps, will be updated from asset

    // Drag mode for the current gesture
    private enum ActiveDrag {
        case scrub
        case leftHandle
        case rightHandle
    }

    @State private var activeDrag: ActiveDrag? = nil

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                thumbnailStrip

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let safeDur = max(dur, 0.0001)

                    let sX = CGFloat(start / safeDur) * w
                    let eX = CGFloat(end   / safeDur) * w
                    let selW = max(0, eX - sX)

                    ZStack {
                        // Dim left of start
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(.black.opacity(0.35))
                                .frame(width: sX)
                                .allowsHitTesting(false)

                            // Selected window
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: selW)
                                .allowsHitTesting(false)

                            // Dim right of end
                            Rectangle()
                                .fill(.black.opacity(0.35))
                                .frame(maxWidth: .infinity)
                                .allowsHitTesting(false)
                        }

                        // Left handle - offset so it stays on screen when at x=0
                        Rectangle()
                            .fill(.white)
                            .frame(width: handleW)
                            .position(x: max(handleW/2, sX), y: h / 2)
                            .allowsHitTesting(false)

                        // Right handle - offset so it stays on screen when at x=w
                        Rectangle()
                            .fill(.white)
                            .frame(width: handleW)
                            .position(x: min(w - handleW/2, eX), y: h / 2)
                            .allowsHitTesting(false)

                        // Playhead (offset slightly right of center to avoid sitting on left handle)
                        Rectangle()
                            .fill(.red)
                            .frame(width: 2)
                            .position(
                                x: CGFloat(playhead / safeDur) * w + 1,
                                y: h / 2
                            )
                            .allowsHitTesting(false)

                        // Single gesture layer: decides once per drag whether
                        // we are scrubbing or moving left/right trim.
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { g in
                                        let totalDur = dur
                                        guard totalDur > 0 else { return }

                                        let w = geo.size.width
                                        let safeDur = max(totalDur, 0.0001)

                                        let sX = CGFloat(start / safeDur) * w
                                        let eX = CGFloat(end   / safeDur) * w

                                        // Decide mode on first drag event
                                        if activeDrag == nil {
                                            let startX = g.startLocation.x
                                            
                                            // Calculate actual visual positions (handles are offset to stay on screen)
                                            let leftHandleX = max(handleW/2, sX)
                                            let rightHandleX = min(w - handleW/2, eX)
                                            
                                            // Extend hit areas outward from handles
                                            // Left handle: extends more to the left (outside)
                                            let leftMin: CGFloat = leftHandleX - handleHitW * 1.5
                                            let leftMax: CGFloat = leftHandleX + handleHitW * 0.5
                                            
                                            // Right handle: extends more to the right (outside)
                                            let rightMin: CGFloat = rightHandleX - handleHitW * 0.5
                                            let rightMax: CGFloat = rightHandleX + handleHitW * 1.5
                                            
                                            let distToLeft  = abs(startX - leftHandleX)
                                            let distToRight = abs(startX - rightHandleX)
                                            
                                            // Check if in hit area and prioritize closest
                                            let inLeftArea = startX >= leftMin && startX <= leftMax
                                            let inRightArea = startX >= rightMin && startX <= rightMax
                                            
                                            if inLeftArea && (!inRightArea || distToLeft <= distToRight) {
                                                activeDrag = .leftHandle
                                            } else if inRightArea {
                                                activeDrag = .rightHandle
                                            } else {
                                                activeDrag = .scrub
                                            }
                                        }

                                        // Current x → normalized [0,1] → time
                                        let clampedX = max(0, min(w, g.location.x))
                                        let norm = clampedX / max(w, 0.0001)
                                        let t = Double(norm) * safeDur

                                        switch activeDrag {
                                        case .scrub:
                                            // Scrub playhead only, constrained to trim range
                                            playhead = max(start, min(t, end))

                                        case .leftHandle:
                                            // Move start, keep at least 0.1s window
                                            var newStart = t
                                            // Do not go beyond end - 0.1
                                            newStart = min(newStart, end - 0.1)
                                            // Clamp not below zero
                                            newStart = max(0, newStart)
                                            start = newStart
                                            // keep playhead inside window
                                            playhead = max(start, min(playhead, end))

                                        case .rightHandle:
                                            // Move end, keep at least 0.1s window
                                            var newEnd = t
                                            newEnd = max(newEnd, start + 0.1)
                                            newEnd = min(totalDur, newEnd)
                                            end = newEnd
                                            // keep playhead inside window
                                            playhead = max(start, min(playhead, end))

                                        case .none:
                                            break
                                        }
                                    }
                                    .onEnded { _ in
                                        activeDrag = nil
                                    }
                            )
                    }
                }
                .frame(height: stripHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.6), lineWidth: 1)
                )
            }

            HStack(spacing: 0) {
                // Left trim time indicator with frame
                Text(timeString(start))
                    .font(.system(size: 18, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
                
                Spacer()
                
                // Transport controls - centered
                HStack(spacing: 28) {
                    // Skip to start
                    Button(action: skipToStart) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 49))
                    }
                    .buttonStyle(.plain)
                    .help("Go to start of trim")
                    
                    // Play/Pause
                    Button(action: togglePlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 49))
                    }
                    .buttonStyle(.plain)
                    .help(isPlaying ? "Pause" : "Play")
                    
                    // Skip to end
                    Button(action: skipToEnd) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 49))
                    }
                    .buttonStyle(.plain)
                    .help("Go to end of trim")
                    
                    Divider()
                        .frame(height: 56)
                    
                    // Loop toggle
                    Button(action: {
                        loopEnabled.toggle()
                        onLoopChanged?(loopEnabled)
                    }) {
                        Image(systemName: loopEnabled ? "repeat.1" : "repeat")
                            .font(.system(size: 49))
                            .foregroundStyle(loopEnabled ? .blue : .primary)
                    }
                    .buttonStyle(.plain)
                    .help("Loop playback")
                }
                
                Spacer()
                
                // Right trim time indicator with frame
                Text(timeString(end))
                    .font(.system(size: 18, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .onAppear { load() }
        .onChange(of: asset) { _, _ in load() }
        .onChange(of: playhead) { _, newValue in
            // Loop playback if enabled and playing
            if loopEnabled && isPlaying && newValue >= end {
                playhead = start
                onSeek?(start)
                onPlay?()  // Restart playback
            }
        }
        .frame(height: stripHeight + 56)
    }

    // MARK: - Thumbnail strip (visual only)
    private var thumbnailStrip: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                ForEach(Array(thumbs.enumerated()), id: \.offset) { _, img in
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w / CGFloat(max(1, thumbs.count)), height: stripHeight)
                        .clipped()
                }
            }
            .frame(height: stripHeight)
            .background(.black.opacity(0.2))
            .cornerRadius(6)
            .allowsHitTesting(false)  // purely visual; gesture comes from overlay
        }
        .frame(height: stripHeight)
    }

    // MARK: - Data
    private func load() {
        Task { @MainActor in
            do {
                let d: CMTime = try await asset.load(.duration)
                var seconds = CMTimeGetSeconds(d)
                if !seconds.isFinite || seconds <= 0 { seconds = 0 }
                dur = seconds
                
                // Get frame rate from video track
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let videoTrack = tracks.first {
                    let nominalFPS = try await videoTrack.load(.nominalFrameRate)
                    fps = Double(nominalFPS > 0 ? nominalFPS : 30.0)
                }
                
                if start == 0 && end == 0 {
                    end = dur
                } else {
                    // Clamp existing start/end into [0, dur]
                    start = max(0, min(start, dur))
                    end   = max(start, min(end, dur))
                }
                if playhead < start || playhead > end {
                    playhead = start
                }
                generateThumbs()
            } catch {
                dur = 0
                thumbs.removeAll()
            }
        }
    }

    private func generateThumbs(count: Int = 8) {
        thumbs.removeAll()

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 320, height: 320)

        let times: [NSValue] = (0..<count).map { i in
            let t = Double(i) / Double(max(1, count - 1)) * dur
            return NSValue(time: CMTime(seconds: t, preferredTimescale: 600))
        }

        var images = Array<NSImage?>(repeating: nil, count: count)

        gen.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cg, _, _, _ in
            guard let cg = cg else { return }
            let idx = times.firstIndex(where: { CMTimeCompare($0.timeValue, requestedTime) == 0 }) ?? 0
            if idx < images.count {
                images[idx] = NSImage(cgImage: cg, size: .zero)
            }
            if images.allSatisfy({ $0 != nil }) {
                DispatchQueue.main.async {
                    thumbs = images.compactMap { $0 }
                }
            }
        }
    }

    private func timeString(_ t: Double) -> String {
        guard t.isFinite else { return "--:--:--" }
        let totalSeconds = max(0, t)
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        let frames = Int((totalSeconds - floor(totalSeconds)) * fps)
        return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }
    
    // MARK: - Transport Controls
    
    private func skipToStart() {
        playhead = start
        onSeek?(start)
    }
    
    private func skipToEnd() {
        playhead = end
        onSeek?(end)
    }
    
    private func togglePlayPause() {
        if isPlaying {
            onPause?()
        } else {
            onPlay?()
        }
    }
}
