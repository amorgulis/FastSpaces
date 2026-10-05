import AppKit
import GestureBridge

@MainActor final class ProbeDelegate: NSObject, NSApplicationDelegate {
 var window: NSWindow!
 var status: NSTextField!
 func applicationDidFinishLaunching(_ notification: Notification) {
  window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 280), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
  window.title = "Fast Spaces — Gesture Probe"
  let view = window.contentView!
  let info = NSTextField(wrappingLabelWithString: "First grant this probe Accessibility access. With at least two Spaces, test Right and Left. Switching uses the display under your pointer. This probe does not intercept keyboard shortcuts.")
  info.frame = NSRect(x: 24, y: 160, width: 492, height: 90); view.addSubview(info)
  status = NSTextField(wrappingLabelWithString: ""); status.frame = NSRect(x: 24, y: 25, width: 492, height: 70); view.addSubview(status)
  let actions: [(String, Selector, CGFloat)] = [("Grant Access", #selector(grant), 24), ("Test Left", #selector(left), 205), ("Test Right", #selector(right), 365)]
  for (title, action, x) in actions {
   let button = NSButton(title: title, target: self, action: action)
   button.frame = NSRect(x: x, y: 110, width: 145, height: 32); view.addSubview(button)
  }
  refresh()
  window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
 }
 func refresh() { status.stringValue = AXIsProcessTrusted() ? "Accessibility granted. Ready to test." : "Accessibility is not granted. Enable Fast Spaces Probe in System Settings → Privacy & Security → Accessibility." }
 @objc func grant() {
  let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
  _ = AXIsProcessTrustedWithOptions(options)
  NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  refresh()
 }
 @objc func left() { post(-1) }
 @objc func right() { post(1) }
 func post(_ direction: Int32) {
  guard AXIsProcessTrusted() else { refresh(); return }
  guard let sequence = FSPrepareSwipe(direction) else { status.stringValue = "Gesture construction failed; nothing was posted."; return }
  FSPostSwipe(sequence); FSReleaseSwipe(sequence)
  status.stringValue = "Posted \(direction == 1 ? "Right" : "Left"). Confirm an actual Space change and check that typing/clicking responds immediately. Posting alone does not prove switching."
 }
 func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

if CommandLine.arguments.contains("--status") {
 print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")")
 exit(AXIsProcessTrusted() ? 0 : 2)
}
if let argument = CommandLine.arguments.dropFirst().first {
 guard argument == "left" || argument == "right" else { print("Usage: GestureProbe [left|right|--status]"); exit(1) }
 guard AXIsProcessTrusted() else { print("Grant Accessibility access to the probe before testing."); exit(2) }
 guard let sequence = FSPrepareSwipe(argument == "right" ? 1 : -1) else { print("Preparation failed"); exit(3) }
 FSPostSwipe(sequence); FSReleaseSwipe(sequence)
 print("Gesture posted. Observe the actual Space change.")
} else {
 let app = NSApplication.shared
 let delegate = ProbeDelegate()
 app.delegate = delegate
 app.setActivationPolicy(.regular)
 app.run()
}
