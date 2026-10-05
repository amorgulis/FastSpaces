# Fast Spaces design

## Purpose and agreed scope

Build a lightweight native macOS menu bar utility that minimizes the time needed to switch to an adjacent Space using Control–Left and Control–Right. The utility replaces the normal shortcut action with a synthetic high-velocity trackpad Dock swipe. Real trackpad swipes are outside this version's scope.

The initial target is the user's Mac running macOS 27.0.1. Success means a visibly faster transition and earlier usable keyboard and mouse input at the destination, without duplicate switches, disabled SIP, or system modifications. Exact latency is measured on the target machine rather than promised in advance.

## Application and components

Use Swift and AppKit for a background menu bar application, with no Dock icon. The menu provides Enable/Disable, permission status, Open Accessibility Settings, and Quit. Preserve the enabled preference between launches. Launch at login and configurable shortcuts are deferred.

An input controller installs a session event tap for keyboard events. It matches Control–Left/Right with no additional Command, Option, or Shift modifiers. Caps Lock does not prevent matching. Other input passes through. Consume matching key events only when the gesture engine is ready. Track consumed key presses so their releases are handled consistently, including when the utility is disabled mid-press. Start with one switch per distinct press; ignore auto-repeat on consumed keys to avoid accidental traversal.

A gesture engine posts the synthetic Dock swipe event sequence for the requested direction. Isolate undocumented event fields and any macOS 27 IOHID payload construction in this component. Mark injected events to prevent feedback if relevant event types are monitored. Serialize injections and bound any pending request to avoid unbounded backlog. The initial rapid-press policy permits at most one pending direction, replacing it with the latest request while an injection is in progress. Do not equate injection completion with confirmed destination readiness.

A permission/lifecycle controller checks Accessibility authorization and event-tap availability. Before readiness, shortcuts pass through. If an event tap is disabled by timeout, re-enable it and surface repeated failures. Clean up the tap on disable or quit. Recheck availability after wake or session changes when needed.

## Technical feasibility gate

Before building the complete UI, compile a small gesture probe and verify an adjacent Space switch on macOS 27.0.1. Consult primary implementation sources, including InstantSpaceSwitcher and joshuarli/iss, for event semantics and version-specific payload requirements. Preserve required license notices for any reused code and document attribution.

Synthetic gesture delivery relies on undocumented macOS behavior. A successful event-post call alone does not prove a switch occurred. If the probe cannot produce a reliable switch, record the failure and revise the design before enabling interception. Do not silently swallow shortcuts with an unverified gesture engine.

## Display and Space behavior

Use the normal synthetic Dock gesture pathway, initially targeting the display under the pointer. Verify this behavior on the target system and explain it in the app's help text. Do not move the pointer automatically. Test ordinary desktops, adjacent full-screen app Spaces, and both ends of the Space list. At an edge, the action should produce no unintended switch.

Multiple displays are a required validation scenario when hardware is available. If no second display is available, explicitly report that behavior as unverified. Direct jumps to numbered Spaces, Mission Control changes, and modifying the system's Space order are excluded.

## Validation and acceptance

Compare baseline Control–Left/Right against the synthetic switch with the same display and Space arrangement. Record a series of transitions in both directions. Separately assess visible transition duration and destination input responsiveness; avoid claims of zero latency based only on appearance.

Verify correct direction, one switch per press, held-key behavior, quick alternating presses, edge behavior, full-screen Spaces, permission denial, disable/enable, quit, event-tap recovery, and nonmatching shortcut passthrough. Unit tests cover shortcut matching and request coordination. Actual gesture behavior requires manual validation on macOS.

Acceptance requires a buildable app bundle, successful switching in both directions on the target Mac, measured or clearly documented observed improvement, no duplicate shortcut actions, and functioning disable/quit behavior. Report any remaining multi-display or lifecycle validation gaps.

## Deliverables

Provide source, a repeatable build command, a runnable app bundle, required license notices, and concise setup instructions. Accessibility permission must be granted by the user through macOS Settings. Distribution signing, notarization, App Store submission, and older macOS compatibility are outside this initial version.
