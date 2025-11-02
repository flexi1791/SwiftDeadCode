import Foundation

// MARK: - Formatting Helpers

/// Formats a byte count into a human-friendly string (e.g. `12.3 MB`).
/// - Parameter value: The byte count to format.
/// - Returns: The human-readable representation.
func formatBytes(_ value: UInt64) -> String {
  if value == 0 { return "0 B" }
  let units = ["B", "KB", "MB", "GB"]
  var amount = Double(value)
  var unitIndex = 0
  while amount >= 1024.0 && unitIndex < units.count - 1 {
    amount /= 1024.0
    unitIndex += 1
  }
  if unitIndex == 0 {
    return "\(value) B"
  }
  return String(format: "%.1f %@", amount, units[unitIndex])
}

/// Pads a string on the left to reach the desired length.
func leftPad(_ text: String, to length: Int) -> String {
  if text.count >= length { return text }
  return String(repeating: " ", count: length - text.count) + text
}

/// Pads a string on the right to reach the desired length.
func rightPad(_ text: String, to length: Int) -> String {
  if text.count >= length { return text }
  return text + String(repeating: " ", count: length - text.count)
}
