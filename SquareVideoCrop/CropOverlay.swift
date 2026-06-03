//CropOverlay.swift
import SwiftUI

/// Square crop overlay that maintains square in PIXEL space, not normalized space.
/// - `videoAspect`: displayed video aspect ratio (width/height) in the preview
/// - `containerSize`: size of the player view the overlay sits on
/// - `videoUprightSize`: actual upright pixel dimensions of the video (e.g., 1920x1080)
/// - `crop`: normalized [0,1] rect (x,y,width,height), top-left origin in preview space
struct SquareCropOverlayStrict: View {
    let videoAspect: CGFloat
    let containerSize: CGSize
    let videoUprightSize: CGSize
    @Binding var crop: CGRect

    // UI tuning
    private let gridLineWidth: CGFloat = 1
    private let handleSize: CGFloat = 14
    private let handleHitSize: CGFloat = 28
    private let borderWidth: CGFloat = 1.5
    private let shadeOpacity: CGFloat = 0.45
    private let minSideNorm: CGFloat = 0.04

    // drag state
    @State private var dragStartCrop: CGRect = .zero
    @State private var activeHandle: Handle? = nil
    private enum Handle { case topLeft, topRight, bottomLeft, bottomRight, body }

    var body: some View {
        let videoRect = innerVideoRect(outer: containerSize, aspect: videoAspect)
        let px = rect(fromNormalized: crop, in: videoRect)

        return ZStack {
            // Dim everything except the video
            Path { p in
                p.addRect(CGRect(origin: .zero, size: containerSize))
                p.addRect(videoRect)
            }
            .fill(Color.black.opacity(shadeOpacity), style: FillStyle(eoFill: true, antialiased: true))

            // Dim inside video outside crop
            Path { p in
                p.addRect(videoRect)
                p.addRect(px)
            }
            .fill(Color.black.opacity(shadeOpacity), style: FillStyle(eoFill: true, antialiased: true))

            // Crop border
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.white.opacity(0.9), lineWidth: borderWidth)
                .frame(width: px.width, height: px.height)
                .position(x: px.midX, y: px.midY)

            // 3x3 grid
            grid(in: px)
                .stroke(Color.white.opacity(0.5), lineWidth: gridLineWidth)

            // SAFETY CIRCLE: shows the circular display area inside the square output (80% of square)
            let circleScale: CGFloat = 0.8
            let circleSize = min(px.width, px.height) * circleScale

            Circle()
                .stroke(Color.white.opacity(0.4), lineWidth: 2)
                .frame(width: circleSize, height: circleSize)
                .position(x: px.midX, y: px.midY)

            // Corner handles
            handle(at: px.origin)
                .gesture(cornerDrag(handle: .topLeft, videoRect: videoRect))
            handle(at: CGPoint(x: px.maxX, y: px.origin.y))
                .gesture(cornerDrag(handle: .topRight, videoRect: videoRect))
            handle(at: CGPoint(x: px.origin.x, y: px.maxY))
                .gesture(cornerDrag(handle: .bottomLeft, videoRect: videoRect))
            handle(at: CGPoint(x: px.maxX, y: px.maxY))
                .gesture(cornerDrag(handle: .bottomRight, videoRect: videoRect))

            // Body drag (move crop)
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: max(0, px.width - handleHitSize),
                       height: max(0, px.height - handleHitSize))
                .position(x: px.midX, y: px.midY)
                .gesture(bodyDrag(videoRect: videoRect))
        }
        .onAppear {
            // Don't override crop on appear - it's already set correctly by ContentView
            // crop = clampedPixelSquare(crop, videoRect: videoRect)
        }
    }

    // MARK: - Gestures

    private func cornerDrag(handle: Handle, videoRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                if activeHandle == nil {
                    activeHandle = handle
                    dragStartCrop = crop
                }
                
                // Work in video pixel space for true square behavior
                let startPxW = dragStartCrop.width * videoUprightSize.width
                let startPxH = dragStartCrop.height * videoUprightSize.height
                let startSide = min(startPxW, startPxH)
                
                // Use dominant axis delta
                let dx = g.translation.width
                let dy = g.translation.height
                let delta = (abs(dx) > abs(dy)) ? dx : dy
                
                // Scale delta to video pixel space
                // Use the dimension that corresponds to the smaller video dimension
                let scaleFactor = min(videoUprightSize.width, videoUprightSize.height) / min(videoRect.width, videoRect.height)
                let deltaPx = delta * scaleFactor
                
                // Calculate new square side in pixels
                var newSidePx = startSide
                switch handle {
                case .topLeft, .bottomLeft:
                    newSidePx = startSide - deltaPx
                case .topRight, .bottomRight:
                    newSidePx = startSide + deltaPx
                case .body:
                    break
                }
                
                // Clamp to video bounds
                let minPx = minSideNorm * min(videoUprightSize.width, videoUprightSize.height)
                newSidePx = max(minPx, min(newSidePx, videoUprightSize.width, videoUprightSize.height))
                
                // Convert back to normalized (CRITICAL: use same pixel size for both dimensions)
                let normW = newSidePx / videoUprightSize.width
                let normH = newSidePx / videoUprightSize.height
                
                var newCrop = dragStartCrop
                newCrop.size = CGSize(width: normW, height: normH)
                
                // Adjust position based on handle
                let startNormW = dragStartCrop.width
                let startNormH = dragStartCrop.height
                
                switch handle {
                case .topLeft:
                    newCrop.origin.x = dragStartCrop.origin.x + (startNormW - normW)
                    newCrop.origin.y = dragStartCrop.origin.y + (startNormH - normH)
                case .topRight:
                    newCrop.origin.y = dragStartCrop.origin.y + (startNormH - normH)
                case .bottomLeft:
                    newCrop.origin.x = dragStartCrop.origin.x + (startNormW - normW)
                case .bottomRight, .body:
                    break
                }
                
                // Clamp position
                newCrop.origin.x = max(0, min(newCrop.origin.x, 1 - normW))
                newCrop.origin.y = max(0, min(newCrop.origin.y, 1 - normH))
                
                crop = newCrop
            }
            .onEnded { _ in
                activeHandle = nil
                crop = clampedPixelSquare(crop, videoRect: videoRect)
            }
    }

    private func bodyDrag(videoRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { g in
                if activeHandle == nil { activeHandle = .body; dragStartCrop = crop }
                var rpx = rect(fromNormalized: dragStartCrop, in: videoRect)
                rpx.origin.x += g.translation.width
                rpx.origin.y += g.translation.height
                rpx = clampSquarePixel(rpx, inside: videoRect)
                crop = normalized(fromPixelRect: rpx, in: videoRect)
            }
            .onEnded { _ in
                activeHandle = nil
                crop = clampedPixelSquare(crop, videoRect: videoRect)
            }
    }

    // MARK: - Geometry helpers

    private func innerVideoRect(outer: CGSize, aspect: CGFloat) -> CGRect {
        guard outer.width > 0, outer.height > 0, aspect > 0 else {
            return CGRect(origin: .zero, size: outer)
        }
        let outerAspect = outer.width / outer.height
        if outerAspect > aspect {
            // letterbox horizontally
            let h = outer.height
            let w = h * aspect
            let x = (outer.width - w) / 2
            return CGRect(x: x, y: 0, width: w, height: h)
        } else {
            // letterbox vertically
            let w = outer.width
            let h = w / aspect
            let y = (outer.height - h) / 2
            return CGRect(x: 0, y: y, width: w, height: h)
        }
    }

    private func rect(fromNormalized r: CGRect, in videoRect: CGRect) -> CGRect {
        CGRect(x: videoRect.minX + r.minX * videoRect.width,
               y: videoRect.minY + r.minY * videoRect.height,
               width:  r.width  * videoRect.width,
               height: r.height * videoRect.height)
    }

    private func normalized(fromPixelRect r: CGRect, in videoRect: CGRect) -> CGRect {
        CGRect(x: (r.minX - videoRect.minX) / videoRect.width,
               y: (r.minY - videoRect.minY) / videoRect.height,
               width:  r.width  / videoRect.width,
               height: r.height / videoRect.height)
    }

    private func clampSquarePixel(_ r: CGRect, inside videoRect: CGRect) -> CGRect {
        var out = r
        let minSidePx = minSideNorm * min(videoRect.width, videoRect.height)

        var side = min(out.width, out.height)
        side = max(side, minSidePx)
        side = min(side, videoRect.width, videoRect.height)

        out.size = CGSize(width: side, height: side)
        out.origin.x = max(videoRect.minX, min(out.origin.x, videoRect.maxX - side))
        out.origin.y = max(videoRect.minY, min(out.origin.y, videoRect.maxY - side))
        return out
    }
    
    // NEW: Clamp to pixel-square in the actual video coordinate space
    private func clampedPixelSquare(_ normRect: CGRect, videoRect: CGRect) -> CGRect {
        // Convert normalized to actual video pixels
        let videoPxW = normRect.width * videoUprightSize.width
        let videoPxH = normRect.height * videoUprightSize.height
        
        // Force square in video pixel space (use smaller dimension)
        let squareSidePx = min(videoPxW, videoPxH)
        
        // Convert back to normalized coordinates
        // CRITICAL: Both dimensions use the SAME pixel size, but different normalized values
        let normW = squareSidePx / videoUprightSize.width
        let normH = squareSidePx / videoUprightSize.height
        
        // Clamp position to keep crop inside video bounds
        var result = normRect
        result.size = CGSize(width: normW, height: normH)
        result.origin.x = max(0, min(result.origin.x, 1 - normW))
        result.origin.y = max(0, min(result.origin.y, 1 - normH))
        
        return result
    }

    // MARK: - Drawing helpers

    private func handle(at point: CGPoint) -> some View {
        ZStack {
            // big invisible hit target
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: handleHitSize, height: handleHitSize)
                .position(point)
            // visible knob
            Circle()
                .fill(Color.white)
                .frame(width: handleSize, height: handleSize)
                .position(point)
                .shadow(color: .black.opacity(0.5), radius: 1)
        }
        .contentShape(Rectangle())
    }

    private func grid(in rect: CGRect) -> Path {
        var p = Path()
        let v1 = rect.minX + rect.width/3
        let v2 = rect.minX + rect.width*2/3
        p.move(to: CGPoint(x: v1, y: rect.minY)); p.addLine(to: CGPoint(x: v1, y: rect.maxY))
        p.move(to: CGPoint(x: v2, y: rect.minY)); p.addLine(to: CGPoint(x: v2, y: rect.maxY))

        let h1 = rect.minY + rect.height/3
        let h2 = rect.minY + rect.height*2/3
        p.move(to: CGPoint(x: rect.minX, y: h1)); p.addLine(to: CGPoint(x: rect.maxX, y: h1))
        p.move(to: CGPoint(x: rect.minX, y: h2)); p.addLine(to: CGPoint(x: rect.maxX, y: h2))
        return p
    }
}
