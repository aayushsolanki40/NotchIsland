# Contributing to NotchIsland

Thanks for helping out! Bug reports, feature ideas and pull requests are all welcome.

## Reporting bugs and requesting features

Use the [issue templates](https://github.com/aayushsolanki40/NotchIsland/issues/new/choose).
For bugs, include your macOS version, Mac model (notch or not), the island style and steps to
reproduce. A screen recording helps a lot with animation or layout problems.

## Development setup

You need macOS 14+ and Xcode 15+ (only the command-line toolchain is used).

```bash
git clone https://github.com/aayushsolanki40/NotchIsland.git
cd NotchIsland
./build.sh && open build/NotchIsland.app
```

`build.sh` compiles every file in `Sources/` with `swiftc` into a universal app bundle and quits
any running copy, so re-running the line above always launches your latest change.

Logs: `log stream --predicate 'process == "NotchIsland"'`.

## Project layout

See [How it works](README.md#how-it-works) in the README. In short: services in `*Service.swift`
publish state, `IslandModel` decides what the island shows and how big it is, and `IslandView`
draws it.

### Changing the app icon

The icon is drawn in code, so there are no design files to keep in sync. Edit
`tools/make-icon.swift`, then regenerate the bundle icon and the README preview:

```bash
swift tools/make-icon.swift /tmp/AppIcon.iconset docs/images/app-icon.png
iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
```

### Adding a live activity

1. Add a case to `Activity` in `IslandModel.swift` and give it a width in `compactSideWidth(for:)`.
2. Trigger it with `showTransient(_:duration:)` (pop-ups) or include it in `primary` (ongoing).
3. Render its leading and trailing content in `CompactView` in `IslandView.swift`.
4. Add a **Preview** item to the menu in `AppDelegate.swift` so others can test it without the real event.

## Coding guidelines

- Match the surrounding style: 4-space indentation, `// MARK:` sections, comments only where the
  *why* isn't obvious.
- Keep the expanded layout heights in `ExpandedLayout` so the island's shape matches its content.
- Never block the main thread — run AppleScript, `Process` and other slow work on a background
  queue, and hop back to main before touching published state.
- Avoid new dependencies; the app builds with the system frameworks only.

## Pull requests

1. Fork the repo and create a branch from `main` (`feature/…` or `fix/…`).
2. Make sure `./build.sh` succeeds with no new warnings and test the change in both island styles.
3. Add an entry under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).
4. Open the PR and fill in the template, with a screenshot or recording for visual changes.

CI builds every pull request; it must pass before merge.

## Releasing (maintainers)

1. Move the **Unreleased** changelog entries under a new version heading.
2. Tag and push: `git tag v1.2.0 && git push origin v1.2.0`.
3. The Build workflow compiles the app, zips it and publishes a GitHub Release with the zip attached.
4. Update the Homebrew cask in [aayushsolanki40/homebrew-tap](https://github.com/aayushsolanki40/homebrew-tap):
   set `version` and `sha256` (`shasum -a 256 NotchIsland.zip`) in `Casks/notchisland.rb`, run
   `brew style` and `brew audit --cask --online` on it, then commit and push.

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
