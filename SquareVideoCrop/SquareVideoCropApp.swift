//SquareVideoCropApp.swift
import SwiftUI
import AppKit

@main
struct SquareVideoCropApp: App {
    @State private var aboutWindow: NSWindow?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 680)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Square Video Crop") {
                    showAboutWindow()
                }
            }
        }
    }
    
    private func showAboutWindow() {
        // Close existing about window if any
        aboutWindow?.close()
        
        let aboutView = AboutView()
        let hosting = NSHostingController(rootView: aboutView)
        
        let window = NSWindow(contentViewController: hosting)
        window.title = "About Square Video Crop"
        window.styleMask = [NSWindow.StyleMask.titled, NSWindow.StyleMask.closable]
        window.standardWindowButton(NSWindow.ButtonType.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(NSWindow.ButtonType.zoomButton)?.isHidden = true
        window.center()  // Initial position
        window.makeKeyAndOrderFront(nil as Any?)
        window.isReleasedWhenClosed = false
        
        // Now reposition relative to main window after it's visible
        DispatchQueue.main.async {
            let appWindows = NSApp.windows.filter {
                $0 != window && ($0.title.contains("Square Video Crop") || $0.contentViewController is NSHostingController<ContentView>)
            }
            
            if let mainWindow = appWindows.first {
                let mainFrame = mainWindow.frame
                let aboutFrame = window.frame
                let x = mainFrame.midX - aboutFrame.width / 2
                let y = mainFrame.midY - aboutFrame.height / 2
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
        
        aboutWindow = window
    }
}
