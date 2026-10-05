@MainActor public protocol TapDriver: AnyObject {
 func start() -> Bool
 func stopWhenReleased()
 func stopImmediately()
}
@MainActor public struct TapLifecycle {
 private let driver: any TapDriver
 public init(driver: any TapDriver) { self.driver = driver }
 public func update(enabled: Bool, available: Bool) -> Bool {
  if available && enabled { return driver.start() }
  if available { driver.stopWhenReleased() } else { driver.stopImmediately() }
  return false
 }
}
public enum SessionEvent: Sendable { case sleep, wake, resign, becomeActive }
public struct SessionState {
 private var sleeping = false
 private var inactive = false
 public init() {}
 public var isSuspended: Bool { sleeping || inactive }
 public mutating func handle(_ event: SessionEvent) {
  switch event {
  case .sleep: sleeping = true
  case .wake: sleeping = false
  case .resign: inactive = true
  case .becomeActive: inactive = false
  }
 }
}
