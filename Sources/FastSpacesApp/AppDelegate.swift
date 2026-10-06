import AppKit
import FastSpacesCore
import GestureBridge

/// Owns a completely prepared gesture, so partial allocation never consumes a shortcut.
final class PreparedSwipe: @unchecked Sendable {
 private let sequence: OpaquePointer
 init?(_ direction: Direction) {
  let prepared = direction == .missionControl ? FSPrepareMissionControl() : FSPrepareSwipe(direction.rawValue)
  guard let sequence = prepared else { return nil }
  self.sequence = sequence
 }
 func post() { FSPostSwipe(sequence) }
 deinit { FSReleaseSwipe(sequence) }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
 private var statusItem: NSStatusItem!
 private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
 private let enabledItem = NSMenuItem(title: "Enable Fast Switching", action: #selector(toggle), keyEquivalent: "")
 private let keyboard = KeyboardTap()
 private let injectionQueue = DispatchQueue(label: "local.fastspaces.injection", qos: .userInteractive)
 private var permissionTimer: Timer?
 private var observers: [NSObjectProtocol] = []
 private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
 private var supported = false
 private var session = SessionState()
 private lazy var lifecycle = TapLifecycle(driver: keyboard)
 private var lastTrusted = false
 private var tapFailure: String?
 private lazy var coordinator = SwitchCoordinator(prepare: { direction in
  guard let swipe = PreparedSwipe(direction) else { return nil }
  return { swipe.post() }
 }, run: { [weak self] job, completion in
  self?.injectionQueue.async {
   job()
   Task { @MainActor in completion() }
  }
 })
 func applicationDidFinishLaunching(_ notification: Notification) {
  statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  statusItem.button?.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Fast Spaces")
  let menu = NSMenu()
  menu.addItem(statusLine)
  menu.addItem(.separator())
  enabledItem.target = self; menu.addItem(enabledItem)
  let permissions = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openPermissions), keyEquivalent: "")
  permissions.target = self; menu.addItem(permissions)
  let help = NSMenuItem(title: "About Fast Spaces…", action: #selector(showHelp), keyEquivalent: "")
  help.target = self; menu.addItem(help)
  menu.addItem(.separator())
  let quit = NSMenuItem(title: "Quit Fast Spaces", action: #selector(quit), keyEquivalent: "q")
  quit.target = self; menu.addItem(quit)
  statusItem.menu = menu
  if ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27, let test = FSPrepareSwipe(1) {
   FSReleaseSwipe(test); supported = true
  }
  keyboard.ready = { [weak self] in
   guard let self else { return false }
   return self.enabled && !self.session.isSuspended && self.supported && self.coordinator.isReady && AXIsProcessTrusted()
  }
  keyboard.switchSpace = { [weak self] direction in
   guard let self else { return false }
   let accepted = self.coordinator.request(direction)
   if !accepted { self.statusLine.title = "Gesture unavailable; shortcut passed through." }
   return accepted
  }
  keyboard.cancelPending = { [weak self] in self?.coordinator.cancelPending() }
  keyboard.failure = { [weak self] message in self?.tapFailure = message; self?.refresh() }
  let center = NSWorkspace.shared.notificationCenter
  let events: [(Notification.Name, SessionEvent)] = [
   (NSWorkspace.willSleepNotification, .sleep),
   (NSWorkspace.didWakeNotification, .wake),
   (NSWorkspace.sessionDidResignActiveNotification, .resign),
   (NSWorkspace.sessionDidBecomeActiveNotification, .becomeActive)
  ]
  for (name, event) in events {
   observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
    MainActor.assumeIsolated { self?.sessionChanged(event) }
   })
  }
  permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
   MainActor.assumeIsolated { self?.refresh() }
  }
  refresh()
 }
 private func refresh() {
  let trusted = AXIsProcessTrusted()
  if trusted != lastTrusted { tapFailure = nil; lastTrusted = trusted }
  let available = supported && trusted && !session.isSuspended && tapFailure == nil
  coordinator.isReady = enabled && available
  let active = lifecycle.update(enabled: enabled, available: available)
  if coordinator.isReady && !active {
   tapFailure = "Keyboard tap unavailable. Toggle Enable to retry."
   coordinator.isReady = false
  }
  enabledItem.state = enabled ? .on : .off
  if !supported { statusLine.title = "Requires the verified macOS 27 gesture path." }
  else if !trusted { statusLine.title = "Accessibility permission required." }
  else if let tapFailure { statusLine.title = tapFailure }
  else if session.isSuspended { statusLine.title = "Paused while session is inactive." }
  else { statusLine.title = enabled ? "Active — Control ← / → / ↑" : "Fast switching disabled." }
 }
 private func sessionChanged(_ event: SessionEvent) {
  session.handle(event)
  if session.isSuspended { coordinator.isReady = false; keyboard.stopImmediately() }
  else { tapFailure = nil }
  refresh()
 }
 @objc private func toggle() {
  enabled.toggle(); tapFailure = nil
  UserDefaults.standard.set(enabled, forKey: "enabled")
  refresh()
 }
 @objc private func openPermissions() {
  _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
 }
 @objc private func showHelp() {
  let alert = NSAlert()
  alert.messageText = "Fast Spaces"
  alert.informativeText = "Control–Left/Right switches to an adjacent Space using a high-velocity gesture. Control–Up opens Mission Control using a fast vertical gesture. Switching targets the display under your pointer. Each press switches once; holding a key does not repeat. Other shortcuts and real trackpad gestures pass through. Uses the gesture pathway you verified on macOS 27."
  alert.addButton(withTitle: "OK")
  NSApp.activate(ignoringOtherApps: true); alert.runModal()
 }
 @objc private func quit() { NSApp.terminate(nil) }
 func applicationWillTerminate(_ notification: Notification) {
  permissionTimer?.invalidate(); keyboard.stopImmediately(); coordinator.isReady = false
  for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
  if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
 }
}
