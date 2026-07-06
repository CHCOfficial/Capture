# Capture

Capture is a native macOS screen recorder built with SwiftUI, AppKit where needed, ScreenCaptureKit, AVFoundation, and AVAssetWriter.

<img width="1355" height="1055" alt="image" src="https://github.com/user-attachments/assets/aafacc2b-def2-4fc8-86a2-52d8768ac54a" />


## Requirements

- macOS 15.0 or later
- Xcode with the macOS SDK selected through `xcode-select`

The project intentionally targets macOS 15.0 because it uses modern ScreenCaptureKit microphone output and mouse-click capture APIs.

## Build

Open `Capture.xcodeproj` in Xcode and run the shared `Capture` scheme.

This workspace currently has only Command Line Tools selected, so `xcodebuild` cannot run here until a full Xcode app is installed and selected:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Prebuilt Mac App

This repository includes a locally built app bundle at:

```sh
open "build/Capture.app"
```

The prebuilt app is intended for local testing. It is:

- Built for Apple Silicon (`arm64`)
- Built for macOS 15.0 or later
- Ad-hoc signed for local launch
- Not notarized by Apple
- Not signed with a Developer ID certificate


## Features

- Display, window, application, and custom-region recording
- Stable live preview for the selected source
- MP4 and MOV output
- HEVC or H.264 encoding through `AVAssetWriter`
- 30 FPS and 60 FPS options
- Native, 1080p, and 720p output sizing
- Optional system audio, microphone audio, or both
- Microphone input selection and live level meter
- Optional cursor and click capture
- Countdown, pause/resume, stop, and safe finalisation
- Floating always-on-top controller
- Optional menu bar status item
- Screen Recording and Microphone permission handling
- Default output folder at `~/Movies/Capture`
- Recent recordings with Reveal, Preview, Rename, Copy Path, Share, and Delete
- Six bundled app icon designs with a Settings picker for changing the Dock icon

## Architecture

- `App`: SwiftUI app entry, AppKit delegate, floating panel, status item
- `Features/Recorder`: main recorder view model and UI
- `Features/SourcePicker`: source selection and region controls
- `Features/Recordings`: completed and recent recording actions
- `Features/Settings`: preferences and shortcut editing
- `Services/Capture`: ScreenCaptureKit source refresh, preview, and recording sessions
- `Services/Encoding`: AVAssetWriter-based media writer
- `Services/Audio`: microphone discovery and level metering
- `Services/Permissions`: mockable permission protocol and system implementation
- `Services/FileSystem`: destination validation, unique filenames, disk checks, sleep assertion
- `Services/Hotkeys`: local/global shortcut monitoring
- `Services/AppIcon`: bundled icon choices and persisted Dock icon switching
- `Models`: recording options, source descriptors, metadata, and state machine
