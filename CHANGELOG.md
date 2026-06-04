# Changelog

All notable changes to Square Video Crop are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `.gitignore` for macOS and Xcode artifacts (`.DS_Store`, `xcuserstate`, `xcuserdata/`, `DerivedData/`, etc.)
- Project `README.md` and this `CHANGELOG.md`

### Changed
- About window is now opened only from the menu, instead of auto-popping 0.5s after every launch

### Removed
- `SquareCropOverlayStrict.swift` — a fully commented-out dead file (the live overlay lives in `CropOverlay.swift`)
- Debug `print()` statements from the export and load paths
- An unused `naturalSize` async load in the export pipeline

## Initial release

The first working version of Square Video Crop — a macOS app for turning landscape or portrait footage into a square clip framed for a circular "video orb" display.

### Crop
- Interactive square crop overlay with draggable corner handles and body drag
- Crop math rebuilt around **true pixel-space squares** so the square stays square in the actual video, not just on screen
- Circular **safety guide** overlay (~80% of the crop area) showing what the round orb display will actually show
- 3×3 framing grid

### Export
- Square, trimmed `.mp4` export via `AVMutableVideoComposition` at highest quality
- **Landscape export** alignment fixed (top-left origin translation)
- **Portrait export** alignment fixed, including correct AVFoundation `preferredTransform` / bottom-left origin handling
- Coordinate handling reconciled across normalized, pixel, preview, and AVFoundation coordinate spaces
- Validated with numbered test-grid footage to confirm preview matches export

### Timeline
- Thumbnail strip with draggable in/out trim handles
- Scrubable red playhead
- Transport controls: play/pause, skip to trim start/end, and loop

### App
- Drag-and-drop and file-picker video loading
- About screen with app info and support QR
- Application icon

### Notes
The trickiest part of the project was eliminating mismatches between the **preview crop** and the **exported crop**, caused by differences between normalized coordinates, pixel coordinates, the preview coordinate system, AVFoundation's coordinate system, and orientation transforms. These were isolated and corrected using custom debug logging, numbered test grids, and validation footage (with assistance from Claude Code during investigation and verification of the transform calculations).
