import AppKit
import FastSpacesCore

/// The run-loop source lives exclusively on the main run loop.
@MainActor final class KeyboardTap: TapDriver {
 private var tap: CFMachPort?
 private var source: CFRunLoopSource?
 private var state = ShortcutState()
 private var accepting = false
 private var timeoutDates: [Date] = []
 var isRunning: Bool { tap != nil }
 var ready: () -> Bool = { false }
 var switchSpace: (Direction) -> Bool = { _ in false }
 var failure: (String) -> Void = { _ in }
 var cancelPending: () -> Void = {}
 func start() -> Bool {
  accepting = true
  if let tap { CGEvent.tapEnable(tap: tap, enable: true); return true }
  guard AXIsProcessTrusted() else { accepting = false; return false }
  let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
  guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
   guard let context else { return Unmanaged.passUnretained(event) }
   let pass = MainActor.assumeIsolated {
    let owner = Unmanaged<KeyboardTap>.fromOpaque(context).takeUnretainedValue()
    return owner.handle(type: type, event: event) != nil
   }
   return pass ? Unmanaged.passUnretained(event) : nil
  }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { accepting = false; return false }
  guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
   CFMachPortInvalidate(port); accepting = false; return false
  }
  tap = port; source = runLoopSource
  CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
  CGEvent.tapEnable(tap: port, enable: true)
  timeoutDates.removeAll()
  return true
 }
 func stopWhenReleased() {
  accepting = false
  cancelPending()
  if !state.hasConsumedKeys { stopImmediately() }
 }
 func stopImmediately() {
  accepting = false; cancelPending(); state.reset()
  if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
  if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
  source = nil; tap = nil
 }
 private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
   cancelPending()
   state.recoverHeldKeys { CGEventSource.keyState(.hidSystemState, key: $0) }
   let now = Date()
   timeoutDates = timeoutDates.filter { now.timeIntervalSince($0) < 10 }
   timeoutDates.append(now)
   if AXIsProcessTrusted(), timeoutDates.count < 3, let tap {
    CGEvent.tapEnable(tap: tap, enable: true)
   } else {
    stopImmediately()
    failure(AXIsProcessTrusted() ? "Keyboard tap repeatedly stopped. Toggle Enable to retry." : "Accessibility permission required.")
   }
   return Unmanaged.passUnretained(event)
  }
  guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
  let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
  let input = KeyInput(code: code, isDown: type == .keyDown, modifiers: Modifiers(rawValue: event.flags.rawValue), isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
  let decision = state.handle(input, ready: accepting && (code == 123 || code == 124) && ready())
  switch decision {
  case .passThrough: return Unmanaged.passUnretained(event)
  case .consume:
   if !accepting && !state.hasConsumedKeys {
    // Remove the source after the current callback returns.
    DispatchQueue.main.async { [weak self] in
     guard let self, !self.accepting, !self.state.hasConsumedKeys else { return }
     self.stopImmediately()
    }
   }
   return nil
  case .switchSpace(let direction):
   if switchSpace(direction) { return nil }
   state.discardConsumedPress(code: code)
   return Unmanaged.passUnretained(event)
  }
 }
}
