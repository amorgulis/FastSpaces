public enum Direction: Int32, Sendable { case previous = -1, next = 1 }
public struct Modifiers: OptionSet, Sendable {
 public let rawValue: UInt64
 public init(rawValue: UInt64) { self.rawValue = rawValue }
 public static let control = Modifiers(rawValue: 1 << 18)
 public static let shift = Modifiers(rawValue: 1 << 17)
 public static let option = Modifiers(rawValue: 1 << 19)
 public static let command = Modifiers(rawValue: 1 << 20)
 public static let capsLock = Modifiers(rawValue: 1 << 16)
 public static let function = Modifiers(rawValue: 1 << 23)
}
public struct KeyInput {
 public let code: UInt16
 public let isDown: Bool
 public let modifiers: Modifiers
 public let isRepeat: Bool
 public init(code: UInt16, isDown: Bool, modifiers: Modifiers, isRepeat: Bool = false) {
  self.code = code; self.isDown = isDown; self.modifiers = modifiers; self.isRepeat = isRepeat
 }
}
public enum KeyDecision: Equatable { case passThrough, consume, switchSpace(Direction) }
public struct ShortcutState {
 private var consumed: Set<UInt16> = []
 public init() {}
 public var hasConsumedKeys: Bool { !consumed.isEmpty }
 public mutating func handle(_ input: KeyInput, ready: Bool) -> KeyDecision {
  if !input.isDown { return consumed.remove(input.code) != nil ? .consume : .passThrough }
  if consumed.contains(input.code) { return .consume }
  guard ready, !input.isRepeat, input.modifiers.contains(.control), input.modifiers.intersection([.command, .option, .shift]).isEmpty else { return .passThrough }
  let direction: Direction
  switch input.code { case 123: direction = .previous; case 124: direction = .next; default: return .passThrough }
  consumed.insert(input.code)
  return .switchSpace(direction)
 }
 public mutating func recoverHeldKeys(isPhysicallyDown: (UInt16) -> Bool) { consumed = consumed.filter(isPhysicallyDown) }
 public mutating func reset() { consumed.removeAll() }
 public mutating func discardConsumedPress(code: UInt16) { consumed.remove(code) }
}
