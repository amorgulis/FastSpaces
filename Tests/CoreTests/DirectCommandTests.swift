import Foundation
import FastSpacesCore

@MainActor func runDirectCommandTests() {
 for (value, direction): (String, Direction) in [("fastspaces://left", .previous), ("fastspaces://right", .next), ("FASTSPACES://LEFT/", .previous), ("fastspaces://up", .missionControl), ("fastspaces://down", .appExpose)] {
  check(DirectCommand.direction(for: URL(string: value)!) == direction, "direct command routes \(value)")
 }
 for value in ["https://left", "fastspaces://unknown", "fastspaces://left/extra", "fastspaces://left?direction=right", "fastspaces://left#right", "fastspaces://user@left", "fastspaces://left:123", "fastspaces:///left"] {
  check(DirectCommand.direction(for: URL(string: value)!) == nil, "invalid direct command rejected: \(value)")
 }
 for command in ["up", "down"] {
  check(DirectCommand.direction(for: URL(string: "fastspaces://\(command)")!, overviewActive: true) == .dismissMissionControl, "\(command) dismisses an active overview")
 }
 check(DirectCommand.direction(for: URL(string: "fastspaces://left")!, overviewActive: true) == .previous, "overview does not change horizontal commands")
}
