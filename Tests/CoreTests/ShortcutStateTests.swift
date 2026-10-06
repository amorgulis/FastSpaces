import FastSpacesCore
@MainActor func runShortcutTests() {
 func key(_ code: UInt16 = 123, down: Bool = true, flags: Modifiers = .control, repeatKey: Bool = false) -> KeyInput {
  KeyInput(code: code, isDown: down, modifiers: flags, isRepeat: repeatKey)
 }
 for code: UInt16 in [125, 126] {
  var dismissal = ShortcutState()
  check(dismissal.handle(key(code), ready: true, missionControlActive: true) == .switchSpace(.dismissMissionControl), "vertical shortcut dismisses active Mission Control")
  check(dismissal.handle(key(code, repeatKey: true), ready: true, missionControlActive: true) == .consume, "dismissal held key suppressed")
  check(dismissal.handle(key(code, down: false), ready: false) == .consume, "dismissal release paired")
 }
 var up = ShortcutState()
 check(up.handle(key(126), ready: true) == .switchSpace(.missionControl), "Control up accepts Mission Control")
 check(up.handle(key(126, repeatKey: true), ready: true) == .consume, "held up does not repeat")
 check(up.handle(key(126, down: false, flags: []), ready: false) == .consume, "up release drains after disable")
 for modifier: Modifiers in [.command, .option, .shift] {
  check(up.handle(key(126, flags: [.control, modifier]), ready: true) == .passThrough, "modified up passes through")
 }
 check(up.handle(key(126), ready: false) == .passThrough, "unready up passes through")
 check(up.handle(key(125), ready: true) == .switchSpace(.appExpose), "Control down opens fast App Expose")
 var state = ShortcutState()
 check(state.handle(key(), ready: true) == .switchSpace(.previous), "Control left switches previous")
 check(state.hasConsumedKeys, "tracks swallowed down")
 check(state.handle(key(repeatKey: true), ready: true) == .consume, "held shortcut never switches twice")
 check(state.handle(key(down: false, flags: []), ready: false) == .consume, "release consumed after disable or modifier release")
 check(!state.hasConsumedKeys, "release clears tracking")
 check(state.handle(key(124, flags: [.control, .capsLock, .function]), ready: true) == .switchSpace(.next), "right accepts caps lock and physical arrow flags")
 state.reset()
 for modifier: Modifiers in [.command, .option, .shift] {
  check(state.handle(key(flags: [.control, modifier]), ready: true) == .passThrough, "extra modifier passes")
 }
 check(state.handle(key(flags: []), ready: true) == .passThrough, "plain arrow passes")
 check(state.handle(key(12), ready: true) == .passThrough, "unrelated key passes")
 check(state.handle(key(), ready: false) == .passThrough, "unready shortcut passes")
 check(state.handle(key(repeatKey: true), ready: true) == .passThrough, "native held key is not captured when enabled")
 check(state.handle(key(down: false), ready: true) == .passThrough, "unconsumed release passes")
 _ = state.handle(key(), ready: true)
 state.discardConsumedPress(code: 123)
 check(state.handle(key(repeatKey: true), ready: true) == .passThrough, "rejected injection repeat passes")
 check(state.handle(key(down: false), ready: true) == .passThrough, "rejected injection release passes")
 _ = state.handle(key(), ready: true)
 state.reset()
 check(!state.hasConsumedKeys, "session reset clears consumed keys")
 _ = state.handle(key(), ready: true)
 _ = state.handle(key(124), ready: true)
 state.recoverHeldKeys { $0 == 123 }
 check(state.handle(key(repeatKey: true), ready: true) == .consume, "timeout preserves physically held consumed repeats")
 check(state.handle(key(down: false), ready: true) == .consume, "timeout preserves paired release")
 check(state.handle(key(124), ready: true) == .switchSpace(.next), "missed release reconciled before new press")
 state.reset()

}
