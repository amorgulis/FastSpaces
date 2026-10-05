# Fast Spaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Build a native menu bar app that accelerates Control–Left/Right switching between adjacent macOS Spaces.

**Architecture:** A Swift package separates shortcut state and request coordination from AppKit lifecycle and a C gesture bridge. First prove synthetic switching on the target Mac, then connect the global keyboard tap. Keep interception disabled until the gesture path is verified.

**Tech Stack:** Swift 6, Swift Package Manager, AppKit, ApplicationServices, C for serialized gesture payloads, XCTest. No third-party runtime dependencies.

**Spec:** [Approved design](fast-spaces-design.md).

## Global Constraints

- Initial target: macOS 27.0.1, Apple Silicon; no older-version compatibility promise.
- Control–Left/Right only; no additional Command, Option, or Shift; Caps Lock permitted.
- One switch per distinct press; consumed auto-repeat ignored.
- At most one pending direction, replaced by the latest request during injection.
- No disabled SIP, system modifications, automatic pointer movement, or real swipe interception.
- Preserve enabled preference; provide Enable/Disable, permission status, Open Accessibility Settings, and Quit.
- User grants Accessibility permission in macOS Settings.
- Measure visible transition and input responsiveness separately; report unavailable hardware tests as unverified.

## Review Focus

- Disable while an arrow is held: no unmatched release or delayed switch; Task 2 state test and Task 4 manual check.
- Accessibility revoked or tap creation fails: native shortcuts continue; Task 4 fault checks.
- Injection construction fails: consume no triggering shortcut and cancel pending work; Tasks 1 and 3 failure tests.
- Wake or session change during a held shortcut: clear stale state and resume only when ready; Tasks 2 and 4 checks.
- Rapid opposite requests: bounded work, consistent direction, no backlog after disable; Task 3 tests and Task 5 manual check.

## File Map

Project root: `outputs/FastSpaces/`. Intermediate observations and downloaded references: `work/`.

- `Package.swift`: core library, C gesture library, app, probe, tests.
- `Sources/GestureBridge/include/GestureBridge.h`, `GestureBridge.c`: macOS 27 gesture construction and posting.
- `Sources/FastSpacesCore/ShortcutState.swift`: pure key matching and consumed-key tracking.
- `Sources/FastSpacesCore/SwitchCoordinator.swift`: serialized bounded requests.
- `Sources/FastSpacesApp/KeyboardTap.swift`: CGEvent tap adapter.
- `Sources/FastSpacesApp/AppDelegate.swift`, `main.swift`: menu, permissions, lifecycle.
- `Sources/GestureProbe/main.swift`: single-direction probe, no keyboard interception.
- `Tests/FastSpacesCoreTests/ShortcutStateTests.swift`, `SwitchCoordinatorTests.swift`: logic tests.
- `Tests/GestureBridgeTests/GestureConstructionTests.swift`: bridge failure and construction checks without posting.
- `Resources/Info.plist`, `scripts/build-app.sh`: background app packaging.
- `README.md`, `THIRD_PARTY_NOTICES.md`, `VALIDATION.md`: setup, licensing, actual validation results.

## Task 1: Prove the gesture path

**Produces:** `FSPrepareSwipe(int direction)` returns an opaque prepared sequence or null; `FSPostSwipe(sequence)` posts it; `FSReleaseSwipe(sequence)` frees it. Direction is -1 for previous, +1 for next. Preparation never posts or changes Spaces.

- [ ] Read and pin the source revision and license of [joshuarli/iss](https://github.com/joshuarli/iss) and compare [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher). Record provenance in `THIRD_PARTY_NOTICES.md` before copying code.
- [ ] Create the package with macOS 27 deployment target and the bridge/probe targets. Add construction tests asserting invalid direction returns null and allocation/serialization failure returns null with no posted events. Introduce an internal injectable allocator/poster seam for these checks.
- [ ] Run `swift test --filter GestureConstructionTests` from the project root; confirm failure because the bridge is not implemented.
- [ ] Implement the bridge using the verified macOS 27 serialized IOHID payload pathway, including paired DockControl/gesture phases. Preserve upstream notices. Prepare the complete sequence before posting, use one synthetic-event marker, and free all temporary allocations. Keep pointer position unchanged.
- [ ] Run the construction tests and `swift build`; require passing tests and successful probe build.
- [ ] Implement `GestureProbe left|right`: validate argument, check authorization, prepare, post once, release, and report that posting is not confirmation of a switch.
- [ ] Run the probe in each direction after Accessibility is granted. Observe the actual Space change, direction, edge behavior, and destination responsiveness. Record OS/build and results in `VALIDATION.md`. If switching fails, investigate the payload before proceeding. Permission denial or unavailable observation is a pending gate, not a successful probe.

## Task 2: Define shortcut state

**Produces:** `Direction { previous, next }`; `KeyInput` with code, down/up, flags, repeat; `KeyDecision { passThrough, consume, switchSpace(Direction) }`; `ShortcutState.handle(_:ready:) -> KeyDecision`, `reset()`, `discardConsumedPress(code: UInt16)` and `hasConsumedKeys`.

- [ ] Write tests: Control+123 down yields previous, Control+124 yields next; Caps Lock accepted; Command/Option/Shift rejected; unrelated and unready input passes; a consumed repeat causes no switch; a consumed release stays consumed after ready becomes false; an unconsumed release passes; reset clears consumed state; discarded rejected presses leave their repeats/releases as passthrough.
- [ ] Run `swift test --filter ShortcutStateTests`; require a failure for the missing implementation.
- [ ] Implement matching and consumed-key tracking in `ShortcutState.swift`, independent of AppKit. Treat the Function flag on physical arrow events consistently rather than rejecting normal arrow events.
- [ ] Rerun the test filter; require all passing, including disable-mid-press and reset scenarios.

## Task 3: Coordinate injections

**Consumes:** Task 1 bridge and Task 2 Direction.
**Produces:** Main-thread-owned `SwitchCoordinator.request(_:) -> Bool`, `cancelPending()`, `isReady`; injectable preparation/posting closures with completion delivered on main. Return false if the request cannot be prepared/accepted. Posting runs on a dedicated serial queue.

- [ ] Write deterministic tests with a held completion: previous starts once; next then previous replace the single pending slot; completion starts only latest pending; cancellation clears it; preparation failure returns false; failure clears pending; disabling allows active sequence to finish but starts nothing further.
- [ ] Run `swift test --filter SwitchCoordinatorTests`; require failure before implementation.
- [ ] Implement the coordinator in `SwitchCoordinator.swift`. Prepare before acceptance. Keep gesture objects alive through posting and release them afterward. Completion means injection ended, not that the destination is interactive.
- [ ] Run the filter and full `swift test`; require all passing. Connect a failed acceptance to keyboard passthrough in Task 4, calling `discardConsumedPress(code:)` to remove the newly recorded consumed state.

## Task 4: Build the menu bar app and input tap

**Consumes:** Tasks 1–3.
**Produces:** `KeyboardTap.start() -> Bool`, `stopWhenReleased()`, `stopImmediately()`, readiness callback and failure callback; AppDelegate owns menu, tap, coordinator and observers.

- [ ] Implement the session keyboard event tap with key-down/up masks and an unretained delegate context whose owner outlives the tap. Call core matching; return null only for consumed input or accepted switches. Pass the original event when acceptance fails. Keep callbacks short and post gestures off the callback thread.
- [ ] On disable, cancel pending work and stop accepting presses; retain the tap until already-consumed keys release, then remove it. On quit or session suspension, stop immediately and clear state. Re-enable timeout-disabled taps; surface repeated failure as unavailable.
- [ ] Implement AppDelegate and entry point with accessory/background activation, the specified menu actions, persistent enabled preference, Accessibility status checks, and wake/session observers. Permission denial, unsupported OS, or tap failure keeps interception off. Explain that switching targets the pointer's display.
- [ ] Package both the app and probe with stable identifiers and ad-hoc signing using `scripts/build-app.sh`; set `LSUIElement` in Info.plist. Document that public distribution signing is deferred.
- [ ] Run `swift test` and `bash scripts/build-app.sh`; require passing tests and a valid app bundle. Run `codesign --verify --strict FastSpaces.app` from the build output; require exit zero.
- [ ] Manually verify permission denial/revocation, tap creation failure, disable while held, quit, wake/session reset, persisted preference, and nonmatching shortcut passthrough. Add actual results to `VALIDATION.md`; never substitute a unit test for global-input observation.

## Task 5: Validate and deliver

- [ ] Compare at least ten baseline and ten accelerated transitions in each direction using the same display, refresh rate, and Spaces. Record the observation method and whether transition duration is measured or visually assessed. Assess destination typing/click response separately.
- [ ] Check held arrows, quick alternating presses, first/last Space, adjacent full-screen apps, and two displays if available. Record pass/fail/unverified for each. Confirm no switches execute after disabling beyond an already-posted sequence.
- [ ] Fix failures and rerun affected tests and manual scenarios. Do not call the gesture path reliable until actual switching is observed on macOS 27.0.1.
- [ ] Write README setup/build instructions and a validation summary with explicit limitations. Deliver source and app bundle under outputs. Confirm license notices ship with both.
- [ ] Run the final full `swift test`, build script, and bundle verification after the last code change. Review the complete implementation against the spec. If execution includes an independent reviewer, resolve actionable findings before delivery.

## Execution Notes

The workspace currently has no Git repository. Keep deliverables in the project directory; do not invent a remote or PR. If repository initialization is chosen during execution, commit each completed task locally. No launch-at-login installation or system preference changes are needed.

The gesture probe is the first execution gate. If macOS requires the user to grant Accessibility permission, finish the build and provide the exact app/probe and Settings instructions before requesting that action. Do not enable interception while this gate is pending.
