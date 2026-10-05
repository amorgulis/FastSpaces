import Foundation
import FastSpacesCore
final class DirectionLog: @unchecked Sendable {
 private let lock = NSLock()
 private var values: [Direction] = []
 func append(_ direction: Direction) { lock.lock(); defer { lock.unlock() }; values.append(direction) }
 var snapshot: [Direction] { lock.lock(); defer { lock.unlock() }; return values }
}
@MainActor func runCoordinatorTests() {
 // The runner records actual accepted jobs; each job captures its immutable direction.
 let posted = DirectionLog()
 var completions: [SwipeCompletion] = []
 var fail = false
 let coordinator = SwitchCoordinator(prepare: { direction in
  if fail { return nil }
  return { posted.append(direction) }
 }, run: { job, completion in job(); completions.append(completion) })
 check(coordinator.request(.previous), "first request accepted")
 check(completions.count == 1, "one injection in flight")
 check(coordinator.request(.next), "pending next accepted")
 check(coordinator.request(.previous), "latest pending accepted")
 check(completions.count == 1, "pending request does not run early")
 if !completions.isEmpty { completions.removeFirst()() }
 check(completions.count == 1, "only latest pending starts after completion")
 check(posted.snapshot == [.previous, .previous], "latest direction replaces pending next")
 coordinator.cancelPending()
 coordinator.isReady = false
 check(!coordinator.request(.next), "disabled rejects new request")
 if !completions.isEmpty { completions.removeFirst()() }
 check(completions.isEmpty, "disable leaves no pending work")
 coordinator.isReady = true
 fail = true
 check(!coordinator.request(.next), "preparation failure rejects request")
 check(completions.isEmpty, "failure does not start injection")
 fail = false
 check(coordinator.request(.next), "recovers after preparation failure")
 check(coordinator.request(.previous), "pending accepted before failure")
 fail = true
 check(!coordinator.request(.next), "pending preparation failure rejected")
 if !completions.isEmpty { completions.removeFirst()() }
 check(completions.isEmpty, "failure clears old pending request")
 check(posted.snapshot == [.previous, .previous, .next], "no cancelled job posted")
}
