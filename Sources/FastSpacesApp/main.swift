import AppKit
import GestureBridge
if CommandLine.arguments.contains("--trace-shortcuts") { setenv("FASTSPACES_TRACE", "1", 1) }
if CommandLine.arguments.contains("--diagnose-spaces") {
 print("Adjacent Space left: \(FSCanSwitchSpace(-1))")
 print("Adjacent Space right: \(FSCanSwitchSpace(1))")
 exit(0)
}
if CommandLine.arguments.contains("--diagnose") {
 let trusted = AXIsProcessTrusted()
 print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
 print("Accessibility: \(trusted ? "granted" : "not granted")")
 if trusted {
  let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
  let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil)
  print("Keyboard tap: \(tap != nil ? "available" : "unavailable")")
  if let tap { CFMachPortInvalidate(tap) }
  exit(tap == nil ? 3 : 0)
 }
 exit(2)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
