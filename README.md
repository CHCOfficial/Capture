# Capture

Capture is a native macOS screen recorder built with SwiftUI, AppKit where needed, ScreenCaptureKit, AVFoundation, and AVAssetWriter.

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

## Support

If Capture is useful to you, you can support development here:

https://buymeacoffee.com/chcofficial

## Licence and Attribution

See `LICENSE.md`. You are welcome to use any part of this project as long as the Buy Me a Coffee link is retained and the original Capture project/creator is credited appropriately.

## Features

- Display, window, application, and custom-region recording
- Stable live preview for the selected source
- MP4 and MOV output
- HEVC or H.264 encoding through `AVAssetWriter`
- 30 FPS and 60 FPS options
- Native (including Retina pixels), 4K, 1440p, 1080p, and 720p output sizing
- Automatic quality presets or a custom video bitrate from 1–500 Mbps
- Visible output dimensions, target bitrate, and estimated video size per minute
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

## Recording Quality

Native records the source's full pixel dimensions, including Retina scaling. Frame rate no longer imposes a hidden resolution limit: 60 FPS retains the selected size. The other resolution choices cap the long edge at 3840, 2560, 1920, or 1280 pixels, preserve the aspect ratio, and never upscale a smaller source. Dimensions are rounded down to even values for encoding.

Start with **Native / High / HEVC / Automatic bitrate** for detailed screen recordings, including video playing inside the screen. Automatic bitrate scales with the actual output pixels, selected frame rate, quality, and codec. For example, High targets about 30 Mbps for HEVC at 1920 × 1080 / 60 FPS; H.264 receives a larger budget. Native Retina recordings can need considerably more storage and encoding power.

Choose **Custom** in the Bitrate picker to set an average target from 1–500 Mbps. This overrides the Quality preset. The output summary displays the actual requested dimensions, target bitrate, and estimated video storage per minute. The encoder uses variable bitrate, so a mostly static screen can produce much smaller files; the target and size estimate are not a guaranteed output rate. Audio and container overhead add slightly to the estimate.

The recorder requests ScreenCaptureKit's best capture resolution and uses HEVC Main / H.264 High profiles with frame reordering allowed. The preview remains small for responsiveness and does not limit the saved recording. If a codec cannot handle a source's native size, select a smaller resolution or another codec; the app reports a failure instead of silently reducing detail.

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
