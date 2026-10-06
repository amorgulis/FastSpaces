import AppKit
import FastSpacesCore
import GestureBridge

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
  var mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
  if CommandLine.arguments.contains("--trace-native-gestures") {
   mask |= (CGEventMask(1) << 29) | (CGEventMask(1) << 30)
  }
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
 private func trace(_ message: String) {
  guard CommandLine.arguments.contains("--trace-shortcuts") || CommandLine.arguments.contains("--trace-native-gestures") else { return }
  let line = "\(Date().timeIntervalSince1970) \(message)\n"
  FileHandle.standardError.write(Data(line.utf8))
 }
 private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
   trace("tap disabled: \(type.rawValue)")
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
  if type.rawValue == 30 && CommandLine.arguments.contains("--trace-native-gestures") {
   let field: (UInt32) -> CGEventField = { CGEventField(rawValue: $0)! }
   let axis = event.getIntegerValueField(field(123))
   let phase = event.getIntegerValueField(field(132))
   trace("native gesture axis=\(axis) phase=\(phase) progress=\(event.getDoubleValueField(field(124))) vx=\(event.getDoubleValueField(field(129))) vy=\(event.getDoubleValueField(field(130)))")
   if axis == 2, let data = event.data {
    let path = "/tmp/FastSpaces-native-\(event.timestamp)-\(phase).bin"
    do { try (data as Data).write(to: URL(fileURLWithPath: path)) }
    catch { trace("capture failed: \(error)") }
   }
  }
  guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
  let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
  let input = KeyInput(code: code, isDown: type == .keyDown, modifiers: Modifiers(rawValue: event.flags.rawValue), isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
  let verticalPress = input.isDown && !input.isRepeat && (code == 125 || code == 126)
   && input.modifiers.contains(.control) && input.modifiers.intersection([.command, .option, .shift]).isEmpty
  let missionControlActive = accepting && verticalPress && FSIsOverviewActive()
  let decision = state.handle(input, ready: accepting && (code == 123 || code == 124 || (code == 125 || code == 126) && !CommandLine.arguments.contains("--trace-native-gestures")) && ready(), missionControlActive: missionControlActive)
  if code == 125 || code == 126 {
   trace("vertical code=\(code) active=\(missionControlActive) down=\(input.isDown) repeat=\(input.isRepeat) accepting=\(accepting) flags=\(input.modifiers.rawValue) decision=\(decision)")
  }
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
   let accepted = switchSpace(direction)
   if code == 125 || code == 126 { trace("Mission Control injection accepted=\(accepted)") }
   if accepted { return nil }
   state.discardConsumedPress(code: code)
   return Unmanaged.passUnretained(event)
  }
 }
}
