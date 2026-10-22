# Snapkit

An open-source screenshot tool for macOS, in the spirit of CleanShot X.
It lives in the menu bar, captures with ScreenCaptureKit, and handles multiple displays and
Retina scaling.

> Status: early development. The MVP features below work; expect rough edges.

## Features

- **Capture area, window or fullscreen** from the menu bar or global shortcuts.
- **Area selection** on a frozen image of every display: dimmed overlay, crosshair guides,
  live pixel size, Shift for a square, Esc or right-click to cancel.
- **Window capture**: hover to highlight, click to capture. Keeps the window's rounded corners
  on a transparent background and adds a drop shadow (optional).
- **Quick Access preview** in the bottom-right corner after each capture: drag it into any app
  as a file, copy, save, annotate, pin or close. Closes itself after a few seconds unless hovered.
- **Annotation editor**: arrow, rectangle, text, highlight, pixelate, blur and numbered
  counters, with colors, three sizes, undo/redo, copy and PNG export at full resolution.
- **Pins**: keep a capture floating above all windows. Drag to move, scroll or pinch to zoom,
  ⌥-scroll to change opacity, right-click for more.
- **Settings**: save folder, file name template, after-capture actions, shortcuts.

## Shortcuts

| Action | Default |
| --- | --- |
| Capture area | ⌥⇧4 |
| Capture window | ⌥⇧5 |
| Capture fullscreen (display under the pointer) | ⌥⇧3 |

All three can be changed in Settings › Shortcuts. The defaults stay off macOS's own ⌘⇧3/4/5;
to use those for Snapkit, turn them off first in System Settings › Keyboard ›
Keyboard Shortcuts › Screenshots.

In the editor: A arrow, R rectangle, T text, H highlight, P pixelate, B blur, N counter;
⌘Z / ⇧⌘Z undo and redo; ⌘C copy; ⌘S save.

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later (Swift 5.9+) to build

## Building

```sh
make app      # builds build/Snapkit.app
make run      # builds, then (re)launches the app
make test     # runs unit tests
CONFIG=release make app
```

Snapkit is a plain Swift package; `open Package.swift` works for editing and running tests in
Xcode. Launch the app through `make run` rather than Xcode's Run button: only the bundled `.app`
gets its own Screen Recording permission.

`make test` skips the tests that take real screenshots. Run them with
`SNAPKIT_INTEGRATION=1 make test` from a terminal that has Screen Recording access; one of them
briefly shows a small test window.

### Code signing

macOS remembers the Screen Recording permission per code signature. With the default ad-hoc
signature you have to grant it again after every rebuild. To avoid that, sign with a stable
identity by creating a `local.mk` (gitignored):

```make
SIGN_IDENTITY = Apple Development: Your Name (TEAMID)
```

`security find-identity -v -p codesigning` lists the identities you have.

## Permissions

Snapkit needs Screen Recording access (System Settings › Privacy & Security ›
Screen & System Audio Recording). On first launch it shows a short guide that opens the right
settings page. macOS sometimes applies a new grant only after a restart of the app; the guide has
a Relaunch button for that. Recent macOS versions also ask now and then to confirm that apps may
keep recording the screen. That prompt comes from the system.

## How it's put together

| Module | What it does |
| --- | --- |
| `SnapkitCore` | Capture model, coordinate conversion, settings, file names, PNG export, clipboard, window shadow |
| `SnapkitCapture` | ScreenCaptureKit wrappers: display and window capture, window list, permission |
| `SnapkitAnnotate` | Annotation model with undo/redo, renderer shared by canvas and export, editor window |
| `Snapkit` | The menu bar app: shortcuts, overlays, Quick Access, pins, settings, onboarding |

A capture goes through `CaptureCoordinator` (permission check, selection UI, ScreenCaptureKit)
and comes out as a `Capture` value: pixels, pixels-per-point scale, and where it was on screen.
`PostCaptureRouter` then runs the after-capture actions the user has enabled.

Coordinates: AppKit uses a bottom-left origin, Quartz and ScreenCaptureKit a top-left origin,
and each display has its own pixel scale. `ScreenGeometry` holds the conversions between these
spaces and is unit-tested.

## Roadmap

Planned for after the MVP, with the extension points already in place:

- Scrolling capture: a new `CaptureMode`, reusing area selection.
- OCR with the Vision framework: another action on a `Capture`, offered in Quick Access.
- Screen recording and GIF export: an SCStream-based service beside `ScreenshotService`.
- Capture history: a consumer of `PostCaptureRouter` that stores each capture.
- Upload and sharing.

## License

MIT, see [LICENSE](LICENSE).
