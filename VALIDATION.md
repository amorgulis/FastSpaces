# Validation status

Target: macOS 27.0.1, build 26A434, arm64; Swift 6.4 command-line tools.

## Observed runtime results

- The user tested the separate gesture probe in both directions and confirmed: “yes they feel immediate.” This satisfies the initial gesture feasibility gate.
- The reported improvement is a visual/perceived observation, not a timed measurement. Destination input responsiveness was not measured separately.
- The user confirmed that the final keyboard shortcut utility works on their Mac after setup. An earlier command-line diagnostic reported missing access (exit 2); it did not install a keyboard tap or post gestures.

## Final build checks

- Optimized release app bundle build: passed.
- Ad-hoc signature verification: passed.
- Full standalone test suite: 77 checks, zero failures.

## Automated verification

The test executable checks actual core behavior and constructs synthetic events without posting them:

- Gesture construction in both directions: complete six-event pairs, phase order, progress sign, terminal velocity, invalid direction and bounds.
- Shortcut matching: exact Control–Left/Right, Caps Lock/function flag handling, extra modifiers and unrelated keys passed through, consumed repeats/releases, failed-injection rollback, session reset.
- Request coordination: serialized jobs, latest pending direction replacement, cancellation, preparation failure, readiness and recovery.
- Lifecycle: disable drains a held consumed press; re-enable restores acceptance before release; missing permission removes the tap; creation failure is not active; sleep and inactive-session gates clear independently.
- Timeout recovery: physically held consumed keys remain suppressed; missed releases are reconciled before the next press.

Each behavior group was observed failing before its implementation and passing afterward. Full CoreTests is the verification command because XCTest is absent from the installed command-line tools. No full Xcode installation is required.

One fresh read-only reviewer identified three important defects (held-key re-enable, timeout recovery, overlapping wake/session state). All were fixed with failing-then-passing regression checks. Optional release dSYM generation is omitted because the build subprocess was sandbox-denied; the executable is still optimized.

## Runtime checks still pending

- Ten baseline and ten accelerated switches in each direction with the same display settings; separate transition/input-readiness timing.
- First/last Space, full-screen app Spaces, multiple displays.
- Real held-key and alternating-key input, permission revocation, timeout recovery, sleep/session recovery, quit and re-enable behavior.

These are not represented as passing by unit tests or code review. The user can perform them after granting final-app access; unavailable display hardware should be recorded as unverified.

## Boundary guard update

- Added regression checks for first/last Space, middle Space, single Space, separate display selection, missing display/current Space, and invalid direction. The unguarded implementation failed nine assertions; the guarded implementation passes all 90 checks.
- Release bundle rebuilt at `dist/Fast Spaces.app`; ad-hoc signature verification passed. Existing command-line-tools cache/search-path warnings remain.
- Every gesture job checks fresh topology at posting time, so queued jobs do not capture an old boundary result. The keyboard still consumes a press whose swipe is suppressed. This does not wait for Dock animation completion.
- Live read-only Space query could not be verified: the sandbox denied WindowServer access (process exit 134), and the user declined the outside-sandbox retry. Live first/last Space and rapid queued-key behavior remain unverified.
