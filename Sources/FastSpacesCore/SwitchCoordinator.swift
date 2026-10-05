public typealias SwipeJob = @Sendable () -> Void
public typealias SwipeCompletion = @MainActor @Sendable () -> Void

/// Completion tracks event injection only, not the Dock's animation or input focus.
@MainActor public final class SwitchCoordinator {
 public var isReady = true { didSet { if !isReady { cancelPending() } } }
 private let prepare: (Direction) -> SwipeJob?
 private let run: (@escaping SwipeJob, @escaping SwipeCompletion) -> Void
 private var active = false
 private var pending: SwipeJob?
 public init(prepare: @escaping (Direction) -> SwipeJob?, run: @escaping (@escaping SwipeJob, @escaping SwipeCompletion) -> Void) {
  self.prepare = prepare; self.run = run
 }
 public func request(_ direction: Direction) -> Bool {
  guard isReady else { return false }
  guard let job = prepare(direction) else { cancelPending(); return false }
  if active { pending = job } else { start(job) }
  return true
 }
 public func cancelPending() { pending = nil }
 private func start(_ job: @escaping SwipeJob) {
  active = true
  run(job) { [weak self] in self?.finished() }
 }
 private func finished() {
  active = false
  guard isReady, let next = pending else { pending = nil; return }
  pending = nil
  start(next)
 }
}
