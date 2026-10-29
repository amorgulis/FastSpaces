import Foundation

/// Only the documented, parameter-free navigation URLs are commands.
public enum DirectCommand {
 public static func direction(for url: URL, overviewActive: Bool = false) -> Direction? {
  guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
   parts.scheme?.lowercased() == "fastspaces",
   parts.user == nil, parts.password == nil, parts.port == nil,
   parts.query == nil, parts.fragment == nil,
   parts.path.isEmpty || parts.path == "/" else { return nil }
  switch parts.host?.lowercased() {
  case "left": return .previous
  case "right": return .next
  case "up": return overviewActive ? .dismissMissionControl : .missionControl
  case "down": return overviewActive ? .dismissMissionControl : .appExpose
  default: return nil
  }
 }
}
