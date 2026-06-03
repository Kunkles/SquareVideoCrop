//
//  AboutView.swift
//  SquareVideoCrop
//
//  Created by Ryan Kunkleman on 11/13/25.
//


//AboutView.swift
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct AboutView: View {
    // ==== Customize as needed ====
    private let makerName   = "Ryan Kunkleman"
    private let venmoHandle = "SecondMealPizzaClub"
    private let venmoQRAssetName = "VenmoQR"          // optional: drop a PNG in Assets with this name
    // ==============================

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Square Video Crop"
    }
    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
    private var venmoURL: URL? {
        URL(string: "https://venmo.com/u/\(venmoHandle)")
    }

    var body: some View {
        VStack(spacing: 14) {
            // App icon (prefer AboutIcon asset if present, else use app icon image)
            if let nsImg = NSImage(named: "AboutIcon") ?? NSApp.applicationIconImage {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .cornerRadius(12)
                    .shadow(radius: 3, y: 1)
            }

            // Title + version
            Text(appName)
                .font(.title2.weight(.semibold))
            Text("Version \(versionString)")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Maker
            Text("Made by \(makerName)")
                .font(.callout)

            // New line
            Text("Buy the developer and his pet AI a beer")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 2)

            // Venmo QR
            VStack(spacing: 8) {
                if NSImage(named: venmoQRAssetName) != nil {
                    // Use provided asset if available
                    Image(venmoQRAssetName)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 180, height: 180)
                        .padding(6)
                        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                } else if let url = venmoURL, let qr = QRCode.make(from: url.absoluteString, size: 180) {
                    // Auto-generate a QR for the Venmo URL if no asset present
                    Image(nsImage: qr)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 180, height: 180)
                        .padding(6)
                        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    // Fallback UI
                    Image(systemName: "qrcode")
                        .font(.system(size: 72, weight: .regular))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 36)
                    Text("Add a \(venmoQRAssetName) image to Assets.xcassets\nor we'll auto-generate from your Venmo URL.")
                        .multilineTextAlignment(.center)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    if let url = venmoURL {
                        Link("Open Venmo", destination: url)
                    }
                    Text("(@\(venmoHandle))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Close") {
                    NSApp.keyWindow?.close()
                }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 340, minHeight: 360)
        .fixedSize(horizontal: false, vertical: true) // let the window auto-fit vertically
    }
}

// MARK: - Simple QR generator
enum QRCode {
    static func make(from string: String, size: CGFloat) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        // Scale crisply
        let scale = max(1, Int(size / ciImage.extent.size.width))
        let transform = CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))
        let scaled = ciImage.transformed(by: transform)

        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
}