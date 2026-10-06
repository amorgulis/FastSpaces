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

## Control–Up extension

- Control–Up routes through the same serialized injection queue using vertical motion, full upward progress and high terminal Y velocity. It bypasses the adjacent-Space boundary query, allowing Mission Control on a single desktop.
- New regression checks first failed for missing shortcut acceptance, held-key/release handling and gesture preparation; the extended suite passes 117 checks.
- Release bundle rebuilt at `dist/Fast Spaces.app`; ad-hoc signature verification passed. Existing cache/search-path warnings remain.
- Live Mission Control opening, direction, animation speed and repeated presses while Mission Control is already open remain unverified. Control–Down is unchanged.

### Control–Up direction correction

- The user reported that the initial Control–Up implementation did nothing. It incorrectly reused negative horizontal progress for the upward vertical gesture.
- Corrected vertical progress and terminal Y velocity to positive values, following the upward direction mapping in the dockswipe reference implementation. Four corrected direction assertions failed before this fix.
- Live confirmation of Mission Control opening and perceived speed is still pending; unit tests verify construction, not Dock behavior.

### Repeated Control–Up investigation

- The user reported only the first opening was fast after closing via native Control–Down. Tracing confirmed every subsequent Control–Up was accepted, paired releases consumed, and a fresh sequence posted; no tap failures appeared.
- Changed vertical began progress from 1 to 0, followed by changed/ended progress 1, to test whether a fresh gesture origin resolves stale Dock state. The new origin regression failed before the change.
- This remains a runtime hypothesis until repeated openings are confirmed; passing construction tests do not prove animation speed.

- Live testing rejected the zero-origin experiment: Control–Up stopped opening Mission Control even though tracing showed successful acceptance/posting. Reverted that experiment.
- Added `--trace-native-gestures` for gathering native Dock-control phase/progress/velocity logs and serialized vertical events in `/tmp/FastSpaces-native-*.bin`. In this diagnostic mode Control–Up passes through to macOS; trackpad gestures are observed unchanged. The repeat-speed issue remains unresolved.

### Native trackpad capture

- Captured three working Mission Control trackpad openings. CGEvent fields reported negative progress/velocity, while the raw field-4205 IOHID payload encoded positive progress and positive identical X/Y terminal velocities. This disproves interpreting the accessor sign as the raw payload direction.
- First native began payload progress was 0.009765625; later phases advanced to 0.3429107666015625 with X/Y velocity 4.0255126953125.
- Synthetic vertical sequence now begins at +0.01, advances to +1, and carries high positive terminal velocity in both X and Y. Two updated assertions failed before this correction; the full suite passes 117 checks. Repeated synthetic openings remain pending live validation.

### IOHID timestamp units

- Subsequent live tests were intermittent; shortcut tracing still confirmed successful interception and posting for each press.
- Native capture header timestamp 350801178298 Mach ticks corresponds approximately to CGEvent timestamp 14616724888708 nanoseconds (41.7 ns/tick). Investigation showed synthetic CGEvents initially had timestamp zero, so the existing Mach-tick fallback was active; a future-timestamp explanation was disproved.
- Assigned explicit CGEvent timestamps and converted nanoseconds to Mach ticks using `mach_timebase_info`, with a 128-bit intermediate to avoid multiplication overflow. Six serialized-payload timestamp checks failed before the correction; the suite passes 123 checks after it.
- This ensures CGEvent and IOHID timestamps are consistent; it is not a confirmed fix for intermittent animation. Consistent repeated Mission Control speed still requires live confirmation.

### Controlled native replay probe

- Added temporary diagnostic `--replay-probe` using the existing Fast Spaces app identity. It replays the first complete captured vertical gesture with refreshed CGEvent/IOHID timestamps, preserving native payload records. It does not install the keyboard replacement tap.
- Buttons compare original phase timing (about 117 ms total), quarter timing (about 29 ms), and burst posting. Close with native Control–Down between attempts.
- `--replay-dry-run` successfully deserialized all eight captured frames and printed their original timing without posting events. Release build/signature and all 123 core checks pass. Runtime replay results remain pending. This diagnostic is a throwaway investigation, not the final acceleration implementation.

- User reported all native replay timing variants were slow, with a focus change after Control–Down in Burst mode. The baseline replay retained normal native velocity; timing alone was insufficient.
- Updated probe with an acceleration checkbox that normalizes captured raw progress to full travel and changes terminal raw X/Y velocities to 9999 while retaining other native metadata. Both baseline and accelerated payload deserialization are checked in dry-run mode. Use Escape between trials to avoid invoking the front-app-window shortcut (Control–Down). Live acceleration comparison remains pending.

## Quarter-timing integration

- User confirmed accelerated native replay at quarter timing is best and works consistently. Native timing and burst replay were slow.
- Integrated that exact accelerated capture path for Control–Up: eight native frames with refreshed timestamps and quarter native phase intervals (about 29 ms total). The native payload metadata is preserved. The capture is bundled in app resources and does not depend on `/tmp`. It is local calibration, not a claim of portability to other hardware or macOS releases.
- Control–Left/Right retain their existing bridge path. Capture loading/preparation failure passes Control–Up through. Injection stays on the existing serial queue. The user confirmed the integrated Control–Up shortcut works.

- User confirmed the final integrated quarter-timing Control–Up shortcut works. This is perceived/live validation on this Mac; quantitative animation timing and other-machine portability remain unverified.

## Capture-free investigation

- Added a generated probe sequence: eight vertical phases, analytic smoothstep progress, per-phase vertical displacement, high X/Y terminal velocities and 4 ms spacing. It constructs IOHID records directly and uses no captured files or device sender identity.
- Probe has a “Generate gesture from code” checkbox enabled by default. Production Control–Up retains the user-verified captured replay until the generated probe passes repeated live tests.

## Final capture-free implementation

- User confirmed the generated quarter-timing probe stays fast and consistent. Control–Up now uses that same `FSPrepareMissionControl` / `FSPostSwipe` sequence on the existing serial injection queue.
- Removed bundled native captures, capture copying from the build script, and the temporary replay probe. The generated sequence does not require local calibration or device sender metadata. Earlier capture/replay sections above document investigation history.
- The user confirmed the final integrated capture-free Control–Up shortcut works well.

## State-aware Mission Control dismissal

- Control–Up and Control–Down request an unmodified Escape pair when Mission Control is detected; Control–Down passes through outside that state. Held presses and releases follow the existing suppression rules.
- Uses an empirical read-only Dock window-layer heuristic (layer 18 present, layer 20 count greater than layer 18), checking on vertical shortcut presses and again immediately before posting dismissal. No retained open/closed toggle is used. Detection can vary with OS/window configuration; live confirmation is pending.
- Matching/detection assertions failed before implementation. Tests also inspect actual Escape event types, key codes, empty modifier flags and bounds.

### macOS 27 dismissal detection correction

- Live trace showed desktop Dock layer18=0/layer20=0 and open Mission Control layer18=0/layer20=1. The earlier layer18 requirement caused Control–Up to request another opening gesture. Control–Down was passing through, so its apparent dismissal did not prove interception worked.
- Added the observed layer20-only pattern to detection, retaining the existing multi-layer pattern and App Exposé exclusion fixture. The new regression failed before the correction. The user confirmed both dismissal shortcuts work.

- User confirmed state-aware Control–Up/Down dismissal works on the target Mac after the layer20-only detector correction.
