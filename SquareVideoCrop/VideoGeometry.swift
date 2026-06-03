//VideoGeometry.swift
import AVFoundation
import CoreMedia
import CoreGraphics
import Foundation

enum VideoGeometry {
    struct Upright {
        let size: CGSize     // upright pixel size (W x H)
        var aspect: CGFloat { size.width / size.height }
    }

    /// Compute upright size from an AVAsset (first video track).
    static func upright(from asset: AVAsset) async throws -> Upright {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let t = tracks.first else {
            throw NSError(domain: "VideoGeometry", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track"])
        }
        return try await upright(from: t)
    }

    /// Compute upright size from a specific AVAssetTrack.
    /// IMPORTANT: We intentionally ignore CleanAperture / PAR here because some
    /// iPhone files report values that do not match what AVPlayer displays,
    /// which caused renderSize like 1080×608. Using only naturalSize + preferredTransform
    /// keeps preview and export in the same coordinate system.
    static func upright(from track: AVAssetTrack) async throws -> Upright {
        let encoded: CGSize = try await track.load(.naturalSize)
        let t: CGAffineTransform = try await track.load(.preferredTransform)

        // Rotate encoded rect by preferredTransform, take bounding box (upright W x H)
        let box = CGRect(origin: .zero, size: encoded).applying(t)
        var w = abs(box.width)
        var h = abs(box.height)

        // Guard against tiny rounding artefacts and make even integers (codec-friendly).
        if w.isFinite == false || h.isFinite == false || w < 2 || h < 2 {
            w = max(2, w)
            h = max(2, h)
        }
        w = floor(w + 0.5)
        h = floor(h + 0.5)

        // Snap extremely close to 16:9 / 9:16 common cases to avoid 1–2 px drift.
        let asp = w / h
        let eps: CGFloat = 0.003
        if abs(asp - (16.0/9.0)) < eps { w = round(h * (16.0/9.0)) }
        if abs(asp - (9.0/16.0)) < eps { h = round(w * (16.0/9.0)) } // keep portrait width

        return Upright(size: CGSize(width: w, height: h))
    }

    /// Convert normalized crop (x,y,w,h in [0,1], origin = top-left in preview)
    /// to an upright pixel rect in the asset’s coordinates.
    static func pixelCropRect(upright: Upright, cropNorm: CGRect) -> CGRect {
        let W = upright.size.width
        let H = upright.size.height
        let x = cropNorm.origin.x * W
        let y = cropNorm.origin.y * H
        let w = cropNorm.size.width  * W
        let h = cropNorm.size.height * H
        return CGRect(x: round(x), y: round(y), width: round(w), height: round(h))
    }
}
