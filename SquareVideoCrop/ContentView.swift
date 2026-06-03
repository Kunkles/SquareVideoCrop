//ContentView.swift
import SwiftUI
@preconcurrency import AVFoundation
import AVKit
import UniformTypeIdentifiers
import AppKit
import CoreMedia

// Avoid Sendable warnings when we pass AVAssetExportSession into closures.
final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ v: T) { value = v }
}

// MARK: - Export pipeline (uses preview's upright size from VideoGeometry)

@MainActor
fileprivate struct SquareTrimExport {
    enum ExportError: Error { case noVideoTrack, cannotMakeExporter, failed(String) }

    final class ExportProgressPoller: NSObject {
        weak var exporter: AVAssetExportSession?
        var timer: Timer?
        let handler: (Float) -> Void
        init(exporter: AVAssetExportSession, handler: @escaping (Float) -> Void) {
            self.exporter = exporter
            self.handler  = handler
        }
        @objc func tick() { if let e = exporter { handler(e.progress) } else { stop() } }
        func start() {
            timer = .scheduledTimer(timeInterval: 0.1,
                                    target: self,
                                    selector: #selector(tick),
                                    userInfo: nil,
                                    repeats: true)
        }
        func stop() { timer?.invalidate(); timer = nil }
    }

    static func exportSquare(
        inputURL: URL,
        start: Double,
        end: Double,
        cropNorm: CGRect,
        previewUprightSize: CGSize,
        outputURL: URL,
        progress: @escaping (Float) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task { @MainActor in
            do {
                let asset = AVURLAsset(url: inputURL)
                let durationCT: CMTime = try await asset.load(.duration)
                let durSec = CMTimeGetSeconds(durationCT)

                let s = max(0, min(start, durSec))
                let e = max(s, min(end, durSec))
                let length = e - s
                guard length > 0 else {
                    completion(.failure(ExportError.failed("Duration <= 0")))
                    return
                }

                let vTracks = try await asset.loadTracks(withMediaType: .video)
                guard let vTrack = vTracks.first else {
                    completion(.failure(ExportError.noVideoTrack))
                    return
                }

                let prefT = try await vTrack.load(.preferredTransform)
                let fps   = max(try await vTrack.load(.nominalFrameRate), 30)

                // Orientation flag from track transform
                let isPortrait = abs(prefT.b) == 1.0 && abs(prefT.c) == 1.0

                // Upright canvas size (what the preview shows)
                let W = previewUprightSize.width
                let H = previewUprightSize.height

                // --- Convert overlay crop to upright TL-normalized rect, then to a
                //     *square* pixel crop centered on what the user framed.

                let original = cropNorm
                let xNormTL = original.minX
                var yNormTL: CGFloat
                let wNorm = original.width
                let hNorm = original.height

                if isPortrait {
                    // Preview crop is TL-based in *display* space; convert to TL in upright space
                    yNormTL = 1.0 - (original.minY + original.height)
                } else {
                    yNormTL = original.minY
                }

                // Center of rect (normalized, upright TL)
                let cxNorm = xNormTL + wNorm / 2.0
                let cyNorm = yNormTL + hNorm / 2.0

                // Size of that rect in pixels (upright)
                let wPxFull = wNorm * W
                let hPxFull = hNorm * H

                // Square side in pixels
                let sidePx = min(wPxFull, hPxFull)

                // Center in pixels
                let cxPx = cxNorm * W
                let cyPx = cyNorm * H

                // TL of square, clamped inside frame
                var xPx = cxPx - sidePx / 2.0
                var yPx = cyPx - sidePx / 2.0
                xPx = max(0, min(xPx, W - sidePx))
                yPx = max(0, min(yPx, H - sidePx))

                let cropPxTL = CGRect(
                    x: round(xPx),
                    y: round(yPx),
                    width: round(sidePx),
                    height: round(sidePx)
                )

                // Render exactly the square crop size (no scaling)
                let cropW = CGFloat(Int(cropPxTL.width.rounded()))
                let cropH = CGFloat(Int(cropPxTL.height.rounded()))

                let vc = AVMutableVideoComposition()
                vc.renderSize = CGSize(width: cropW, height: cropH)

                vc.frameDuration = CMTime(value: 1, timescale: Int32(fps))

                let timeRange = CMTimeRange(
                    start: CMTime(seconds: s, preferredTimescale: 600),
                    duration: CMTime(seconds: length, preferredTimescale: 600)
                )

                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = timeRange

                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)

                // --- Transform
                //
                // For landscape (prefT is usually a flip), translating from TL works well.
                // For portrait (prefT is a 90° rotate), translating from BL matches what
                // AVFoundation expects and lines up with the preview crop.

                let tFinal: CGAffineTransform
                if isPortrait {
                    // Use bottom-left for portrait to correct the vertical offset
                    let xBL = cropPxTL.minX
                    let yBL = H - (cropPxTL.minY + cropPxTL.height)
                    let tTranslate = CGAffineTransform(translationX: -xBL, y: -yBL)
                    tFinal = prefT.concatenating(tTranslate)
                } else {
                    // Landscape: keep the TL-based behavior that’s working well
                    let xTL = cropPxTL.minX
                    let yTL = cropPxTL.minY
                    let tTranslate = CGAffineTransform(translationX: -xTL, y: -yTL)
                    tFinal = prefT.concatenating(tTranslate)
                }

                layer.setTransform(tFinal, at: .zero)
                inst.layerInstructions = [layer]
                vc.instructions = [inst]

                guard let exporter = AVAssetExportSession(asset: asset,
                                                          presetName: AVAssetExportPresetHighestQuality)
                else {
                    completion(.failure(ExportError.cannotMakeExporter))
                    return
                }

                exporter.timeRange = timeRange
                exporter.videoComposition = vc
                exporter.shouldOptimizeForNetworkUse = true
                exporter.outputFileType = .mp4

                try? FileManager.default.removeItem(at: outputURL)

                if #available(macOS 15.0, *) {
                    try await exporter.export(to: outputURL, as: .mp4)
                    completion(.success(outputURL))
                } else {
                    exporter.outputURL = outputURL

                    let poller = ExportProgressPoller(exporter: exporter, handler: progress)
                    poller.start()

                    let box = UncheckedBox(exporter)
                    exporter.exportAsynchronously {
                        let e = box.value
                        poller.stop()
                        DispatchQueue.main.async {
                            switch e.status {
                            case .completed:
                                completion(.success(outputURL))
                            case .failed, .cancelled:
                                completion(.failure(ExportError.failed(
                                    e.error?.localizedDescription ?? "Export failed"
                                )))
                            default:
                                break
                            }
                        }
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}

// MARK: - UI

struct ContentView: View {
    @State private var inputURL: URL?
    @State private var player: AVPlayer?
    @State private var asset: AVAsset?
    @State private var uprightPx: CGSize = .zero
    @State private var startTime: Double = 0
    @State private var endTime: Double   = 0
    @State private var playhead: Double  = 0
    @State private var cropNorm: CGRect = .zero
    @State private var isWorking = false
    @State private var progress: Float = 0
    @State private var isPlaying = false
    @State private var isSeekingFromUser = false  // Prevent feedback loop
    @State private var isLooping = false  // Track loop state
    @State private var status = "Drop a video to begin."

    var body: some View {
        VStack(spacing: 12) {
            header

            ZStack {
                if let player {
                    GeometryReader { geo in
                        let container = geo.size
                        let aspect = (uprightPx.width > 0 && uprightPx.height > 0)
                        ? (uprightPx.width / uprightPx.height)
                        : (9.0/16.0)

                        ZStack {
                            VideoPlayerView(player: player)
                            SquareCropOverlayStrict(
                                videoAspect: aspect,
                                containerSize: container,
                                videoUprightSize: uprightPx,
                                crop: $cropNorm
                            )
                            .allowsHitTesting(true)
                        }
                    }
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.5)))
                } else {
                    dropZone.frame(height: 320)
                }
            }

            if let asset {
                // Instructions
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Drag the white handles on the timeline to set trim points")
                    Text("• Drag the red playhead to scrub through the video")
                    Text("• Drag corner handles on the video to adjust the crop area")
                    Text("• The white circle shows the safe area that will be visible on circular displays")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                
                TimelineTrimmer(
                    asset: asset,
                    start: $startTime,
                    end: $endTime,
                    playhead: $playhead,
                    onPlay: {
                        player?.play()
                        isPlaying = true
                    },
                    onPause: {
                        player?.pause()
                        isPlaying = false
                    },
                    onSeek: { time in
                        let t = CMTime(seconds: time, preferredTimescale: 600)
                        player?.seek(to: t,
                                     toleranceBefore: .zero,
                                     toleranceAfter: .zero,
                                     completionHandler: { _ in })
                    },
                    isPlaying: isPlaying,
                    onLoopChanged: { enabled in
                        isLooping = enabled
                    }
                )
                .frame(maxWidth: .infinity)
                .onChange(of: playhead) { _, new in
                    // Only seek if the change came from user interaction, not from the time observer
                    if !isPlaying {
                        let t = CMTime(seconds: new, preferredTimescale: 600)
                        player?.seek(to: t,
                                     toleranceBefore: .zero,
                                     toleranceAfter: .zero,
                                     completionHandler: { _ in })
                    }
                }
            }

            // Telemetry info (commented out)
            /*
            if uprightPx != .zero {
                let renderSide = Int(min(uprightPx.width * cropNorm.width,
                                         uprightPx.height * cropNorm.height).rounded())
                Text(String(format: "Crop (norm): %.3f, %.3f  %.3f x %.3f    Upright px: %.0f x %.0f  ->  Render: %d x %d",
                            cropNorm.origin.x, cropNorm.origin.y, cropNorm.width, cropNorm.height,
                            uprightPx.width, uprightPx.height, renderSide, renderSide))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            */

            if isWorking {
                ProgressView(value: Double(progress))
                    .progressViewStyle(.linear)
            }

            HStack {
                Button(action: chooseFile) { Text("Choose File…") }
                Spacer()
                Button(action: export) {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(isWorking ? "Exporting…" : "Export")
                }
                .disabled(isWorking || inputURL == nil)
            }

            if !status.isEmpty && status != "Ready." {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .onDisappear { player?.pause() }
    }

    private var header: some View {
        HStack {
            Text("Square Video Crop").font(.title2.bold())
            Spacer()
            if let name = inputURL?.lastPathComponent {
                Text(name).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("Drop a video file here").font(.headline).foregroundStyle(.secondary)
                Text("MP4 / MOV").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { load(url) } }
            }
            return true
        }
    }

    private func chooseFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [
            .movie,
            UTType(filenameExtension: "mp4")!,
            UTType(filenameExtension: "mov")!
        ]
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        if p.runModal() == .OK, let url = p.url { load(url) }
    }

    private func load(_ url: URL) {
        inputURL = url
        status = "Loading…"

        let a = AVURLAsset(url: url)
        asset = a

        Task { @MainActor in
            do {
                let u = try await VideoGeometry.upright(from: a)
                uprightPx = u.size

                let d: CMTime = try await a.load(.duration)
                let secs = max(0, CMTimeGetSeconds(d))
                startTime = 0
                endTime   = secs
                playhead  = 0

                let W = uprightPx.width
                let H = uprightPx.height
                let squareSide = min(W, H)

                let normW = squareSide / W
                let normH = squareSide / H
                let normX = (1.0 - normW) / 2.0
                let normY = (1.0 - normH) / 2.0

                cropNorm = CGRect(x: normX, y: normY, width: normW, height: normH)

                let item = AVPlayerItem(asset: a)
                let p = AVPlayer(playerItem: item)
                player = p
                p.actionAtItemEnd = .pause
                p.seek(to: .zero,
                       toleranceBefore: .zero,
                       toleranceAfter: .zero,
                       completionHandler: { _ in })
                // Add periodic time observer to update playhead during playback
                // Use 15 FPS for smoother performance
                let interval = CMTime(seconds: 0.067, preferredTimescale: 600)
                p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
                    guard let p = p else { return }
                    let currentTime = CMTimeGetSeconds(time)
                    if p.rate > 0 { // Only update if playing
                        playhead = currentTime
                        // Auto-pause at end of trim (unless looping)
                        if currentTime >= endTime && !isLooping {
                            p.pause()
                            isPlaying = false
                        }
                    }
                }

                status = "Ready."
            } catch {
                status = "Error loading: \(error.localizedDescription)"
            }
        }
    }

    private func export() {
        guard let inputURL else { status = "No input."; return }

        let c = cropNorm
        let base = inputURL.deletingPathExtension().lastPathComponent
        let sp = NSSavePanel()
        sp.allowedContentTypes = [UTType(filenameExtension: "mp4")!]
        sp.isExtensionHidden = false
        sp.canCreateDirectories = true
        sp.nameFieldStringValue = "\(base)-sqtrim.mp4"
        sp.title = "Export Square Video"
        sp.prompt = "Export"

        guard sp.runModal() == .OK, let out = sp.url else {
            status = "Export canceled."
            return
        }

        let startedIn  = inputURL.startAccessingSecurityScopedResource()
        let startedOut = out.startAccessingSecurityScopedResource()

        isWorking = true
        progress  = 0
        status    = "Exporting…"

        SquareTrimExport.exportSquare(
            inputURL: inputURL,
            start: startTime,
            end: endTime,
            cropNorm: c,
            previewUprightSize: uprightPx,
            outputURL: out,
            progress: { p in self.progress = p },
            completion: { result in
                self.isWorking = false

                if startedIn { inputURL.stopAccessingSecurityScopedResource() }
                if startedOut { out.stopAccessingSecurityScopedResource() }

                switch result {
                case .success(let url):
                    self.status = "Saved: \(url.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                case .failure(let err):
                    self.status = "Error: \(err.localizedDescription)"
                }
            }
        )
    }
}
