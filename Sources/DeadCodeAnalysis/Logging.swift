import Foundation

extension DeadCodeAnalysis {
  enum Logger {
    /// Writes a status message to stderr so Xcode/SwiftPM capture progress updates.
    static func logStatus(_ message: String) {
      let line = "\(message)\n"
      if let data = line.data(using: .utf8) {
        FileHandle.standardError.write(data)
      }
    }

    /// Emits verbose logging when the corresponding flag is enabled.
    static func logVerbose(_ enabled: Bool, _ message: @autoclosure () -> String) {
      if enabled {
        logStatus(message())
      }
    }
  }
}
