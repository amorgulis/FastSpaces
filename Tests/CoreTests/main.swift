import Foundation
import GestureBridge
import FastSpacesCore
var failures = 0
var checks = 0
@MainActor func check(_ value: Bool, _ name: String) {
 checks += 1
 if !value { failures += 1; print("FAIL: \(name)") }
}
check(FSPrepareSwipe(0) == nil, "invalid direction rejected")
check(FSPrepareSwipe(2) == nil, "invalid direction rejected")
for direction: Int32 in [-1, 1] {
 guard let sequence = FSPrepareSwipe(direction) else { check(false, "valid swipe must prepare"); continue }
 defer { FSReleaseSwipe(sequence) }
 for index: Int32 in 0..<6 {
  guard let event = FSCopySequenceEvent(sequence, index)?.takeRetainedValue() else { check(false, "complete sequence"); continue }
  check(event.getIntegerValueField(CGEventField(rawValue: 55)!) == (index % 2 == 0 ? 30 : 29), "paired event type")
  if index % 2 == 0 {
   check(event.getIntegerValueField(CGEventField(rawValue: 132)!) == [1, 2, 4][Int(index/2)], "phase order")
   check(event.getDoubleValueField(CGEventField(rawValue: 124)!) == (direction == 1 ? -1 : 1), "direction")
   if index == 4 { check(event.getDoubleValueField(CGEventField(rawValue: 129)!) == (direction == 1 ? -9999 : 9999), "terminal velocity") }
  }
 }
 check(FSCopySequenceEvent(sequence, 6) == nil, "event bounds")
}
runShortcutTests()
runCoordinatorTests()
runLifecycleTests()
print("Checks: \(checks), failures: \(failures)")
exit(failures == 0 ? 0 : 1)
