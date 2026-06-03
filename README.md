# Square Video Crop

A small macOS app for cropping and trimming video into a **square clip centered for a circular "video orb" ornament** — a round display that only shows the middle of a square frame.

Because the orb is circular, the part of your video that actually shows is the inscribed circle of the square crop. Square Video Crop gives you a live preview with a safety circle so you can frame your subject inside what the orb will display, trim the clip down, and export a ready-to-use `.mp4`.

## Features

- **Drag-and-drop** a `.mp4` / `.mov`, or pick one with a file dialog
- **Live square crop overlay** with draggable corner handles and body drag
  - The crop stays square in *actual video pixels*, not just on-screen
  - A **safety circle** (80% of the square) shows what the round orb display will actually show
- **Timeline trimmer** with a thumbnail strip, draggable in/out handles, and a scrubable red playhead
- **Transport controls** — play/pause, skip to trim start/end, and loop
- **Correct orientation handling** for both portrait and landscape source video
- **High-quality export** to square `.mp4`, cropped and trimmed to your selection

## Requirements

- macOS 13+ (uses the modern async AVFoundation APIs; macOS 15+ takes the newest export path)
- Xcode 15 or later to build

## Building

```bash
git clone https://github.com/Kunkles/SquareVideoCrop.git
cd SquareVideoCrop
open SquareVideoCrop/SquareVideoCrop.xcodeproj
```

Then build and run the **SquareVideoCrop** scheme in Xcode (⌘R).

## Usage

1. Launch the app and drop a video onto the window (or click **Choose File…**).
2. Drag the **corner handles** on the video to set your square crop. Keep your subject inside the circle — that's all the orb will show.
3. Drag the **white handles** on the timeline to set trim in/out points, and drag the **red playhead** to scrub.
4. Click **Export** and choose where to save the square `.mp4`.

## How it works

- `VideoGeometry` computes the upright pixel size from the track's `naturalSize` and `preferredTransform`, so the preview and export share one coordinate system.
- `CropOverlay` keeps the crop square in video-pixel space and renders the safety circle.
- The export pipeline in `ContentView` builds an `AVMutableVideoComposition`, translating the crop into the source's coordinate space (bottom-left origin for portrait, top-left for landscape) and rendering exactly the square crop with no scaling.

## License

No license specified yet — all rights reserved by default. Add a `LICENSE` file if you want to allow reuse.
