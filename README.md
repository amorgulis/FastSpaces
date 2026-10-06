# Fast Spaces

A native macOS 27 menu bar utility for fast adjacent-Space switching with **Control–Left** and **Control–Right**, plus a fast vertical Mission Control gesture with **Control–Up**. The high-velocity gesture probe was confirmed by the user to switch immediately in both directions on macOS 27.0.1. The user also confirmed that the final Control–Left/Right shortcut utility works. Quantitative timing and the remaining edge-case checks are unverified.

## Setup

1. Quit Fast Spaces Probe if it is open.
2. Open `../Fast Spaces.app`. Look for the left/right arrow icon in the menu bar; the app has no Dock icon.
3. Click the icon → **Open Accessibility Settings…**. Enable **Fast Spaces** in System Settings → Privacy & Security → Accessibility. This is a separate app from the probe, so it needs its own permission. If absent, use + to add Fast Spaces.app.
4. The menu changes to **Active — Control ← / → / ↑** after permission is detected, usually within two seconds. If macOS still reports missing access, quit and reopen the app.
5. Use Control–Left/Right to switch Spaces, or Control–Up to open Mission Control. Each press switches once; holding the key does not repeat. Switching targets the display under the pointer. Outward presses at the first or last Space are consumed without posting a gesture.

**Enable Fast Switching** pauses/resumes the shortcut replacement and persists across launches. When disabled or missing permission, the normal macOS shortcuts pass through. **Quit Fast Spaces** removes the keyboard tap. Other modifier combinations and actual trackpad gestures are left alone.

To keep the app elsewhere, move it before granting Accessibility permission. This build is locally ad-hoc signed; signing/notarization for public distribution is not included. No SIP changes, Dock preference modifications, launch agents, or login item installation are required.

## Build and verify

Requires Swift 6 and macOS 27 command-line tools; no runtime dependencies or full Xcode installation.

```sh
bash scripts/test.sh
bash scripts/build-app.sh
```

Optional gesture probe: `bash scripts/build-probe.sh`. Each script places its app alongside this source folder. Build caches stay within `.build`.

Diagnostic command, from the folder containing the app:

```sh
"Fast Spaces.app/Contents/MacOS/FastSpacesApp" --diagnose
```

Exit 0 means Accessibility and keyboard-tap creation were available to that process; exit 2 means missing Accessibility and exit 3 means tap creation failed. This command does not post gestures or verify switching. macOS can attribute command-line permission checks to the launching application differently from opening the bundle normally.

## Architecture and limits

`FastSpacesCore` matches key presses and tracks consumed releases, and serializes gesture jobs with at most one pending request. `FastSpacesApp` owns the menu, Accessibility checks, event tap and lifecycle. `GestureBridge` constructs a complete paired gesture sequence before a shortcut is accepted; posting runs on a dedicated serial queue.

Control–Up constructs an eight-phase vertical gesture directly in code, with smooth progress, high terminal velocity and 4 ms phase spacing (about 28 ms of injection). The user confirmed the generated gesture stays fast and consistent. No captured gesture files or device calibration are required.

The bridge uses undocumented macOS 27 event fields and IOHID payloads adapted from joshuarli/iss (0BSD). Future major macOS versions remain disabled until verified. See THIRD_PARTY_NOTICES.md for the pinned revision and license, and VALIDATION.md for the exact test coverage and remaining runtime checks.

Space boundary diagnostic (read-only, no gestures):

```sh
"dist/Fast Spaces.app/Contents/MacOS/FastSpacesApp" --diagnose-spaces
```

The bridge reads the current ordered Space list immediately before each queued swipe is posted, including full-screen Spaces. If the display or Space topology cannot be read, it suppresses the swipe. These read-only SkyLight APIs are undocumented and resolved dynamically.
