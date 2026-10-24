# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- App icon: a pill with equalizer bars beside a bubble holding album art.
- Menu bar icon now matches the app icon (pill and bubble) and follows light/dark appearance.

## [1.0.1] - 2026-10-24

### Fixed
- Album art missing for some songs: Apple Music streaming tracks now get their cover from the iTunes
  Search API, Spotify covers that arrive late are retried, and the previous song's cover is cleared
  immediately on a track change.
- Catalog lookup now searches the listener's own storefront and tolerates artist spelling variants,
  so regional songs like Indian releases find their cover.

### Added
- Install with Homebrew: `brew install --cask aayushsolanki40/tap/notchisland`.

## [1.0.0] - 2026-10-24

### Added
- Island that sits in the notch and expands on hover or click, with Notch and floating iPhone Pill styles.
- Now Playing for Music and Spotify: artwork, tinted waveform, drag-to-seek progress bar and playback controls.
- Timer with presets, pause/cancel, completion chime and split bubble alongside music.
- Charging, low-battery (20 % / 10 %), AirPods/Bluetooth and volume pop-ups.
- Swipe (two-finger or click-drag) to hide an activity.
- Menu bar menu with style, hover, launch-at-login and preview options.

[Unreleased]: https://github.com/aayushsolanki40/NotchIsland/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/aayushsolanki40/NotchIsland/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/aayushsolanki40/NotchIsland/releases/tag/v1.0.0
