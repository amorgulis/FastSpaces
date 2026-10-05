import FastSpacesCore
@MainActor final class FakeTap: TapDriver {
 var running = true
 var accepting = true
 var holdingConsumed = true
 var startSucceeds = true
 func start() -> Bool { running = startSucceeds; accepting = startSucceeds; return startSucceeds }
 func stopWhenReleased() { accepting = false; if !holdingConsumed { running = false } }
 func stopImmediately() { accepting = false; running = false; holdingConsumed = false }
}
@MainActor func runLifecycleTests() {
 let tap = FakeTap()
 let lifecycle = TapLifecycle(driver: tap)
 check(!lifecycle.update(enabled: false, available: true), "disable not active")
 check(tap.running && !tap.accepting, "disable drains consumed press")
 check(lifecycle.update(enabled: true, available: true), "re-enable becomes active")
 check(tap.running && tap.accepting, "re-enable before release restores acceptance")
 check(!lifecycle.update(enabled: true, available: false), "permission failure not active")
 check(!tap.running && !tap.accepting, "unavailable removes tap immediately")
 tap.startSucceeds = false
 check(!lifecycle.update(enabled: true, available: true), "tap creation failure not active")
 var session = SessionState()
 session.handle(.resign); session.handle(.sleep); session.handle(.wake)
 check(session.isSuspended, "wake does not reactivate inactive session")
 session.handle(.becomeActive)
 check(!session.isSuspended, "active awake session resumes")
 session.handle(.sleep); session.handle(.resign); session.handle(.becomeActive)
 check(session.isSuspended, "active session does not clear sleep")
 session.handle(.wake)
 check(!session.isSuspended, "both gates cleared resumes")
}
