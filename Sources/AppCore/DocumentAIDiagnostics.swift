import Foundation

/// Provider errors are diagnostic JSON, separate from unmodified successful response data.
enum DocumentAIDiagnostics {
  static func sanitize(_ data: Data, tokens: [String]) -> Data {
    guard data.count <= 1_048_576,
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let error = root["error"] as? [String: Any] else { return Data() }
    let sanitized = redact(error, tokens: tokens, depth: 0)
    return (try? JSONSerialization.data(withJSONObject: ["error": sanitized], options: [.sortedKeys])) ?? Data()
  }

  private static func redact(_ value: Any, tokens: [String], depth: Int) -> Any {
    guard depth < 32 else { return "[REDACTED]" }
    if let object = value as? [String: Any] {
      var result: [String: Any] = [:]
      for (key, value) in object {
        let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
        let sensitive = ["authorization", "accesstoken", "refreshtoken", "idtoken", "privatekey", "clientsecret",
                         "password", "credential", "apikey", "rawdocument", "inlinedocument", "content"]
        let safeKey = scrub(key, tokens: tokens)
        result[safeKey] = sensitive.contains(where: { normalized.contains($0) }) ?
          "[REDACTED]" : redact(value, tokens: tokens, depth: depth + 1)
      }
      return result
    }
    if let array = value as? [Any] { return array.map { redact($0, tokens: tokens, depth: depth + 1) } }
    if let string = value as? String { return scrub(string, tokens: tokens) }
    return value
  }

  private static func scrub(_ value: String, tokens: [String]) -> String {
    var result = value
    for token in tokens.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
      result = result.replacingOccurrences(of: token, with: "[REDACTED]")
    }
    result = result.replacingOccurrences(
      of: "(?i)Bearer[ \\t]+[^\\s,;]+", with: "Bearer [REDACTED]", options: .regularExpression
    )
    result = result.replacingOccurrences(
      of: "(?s)-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",
      with: "[REDACTED]", options: .regularExpression
    )
    return result
  }
}
