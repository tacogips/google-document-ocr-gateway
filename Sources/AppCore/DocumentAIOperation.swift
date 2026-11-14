import Foundation

/// Decodes control fields only. The complete operation remains raw JSON in returned data.
struct DocumentAIOperation: Decodable {
  struct Status: Decodable { let code: Int }
  let name: String
  let done: Bool?
  let error: Status?

  static func validateTiming(timeout: TimeInterval, interval: TimeInterval) throws {
    guard timeout.isFinite, timeout > 0, interval.isFinite, interval > 0 else {
      throw DocumentAIError.invalidArgument("Timeout and poll interval must be positive and finite")
    }
  }

  static func decode(_ data: Data) throws -> Self {
    do { return try JSONDecoder().decode(Self.self, from: data) } catch { throw DocumentAIError.transport }
  }
}

extension DocumentAIClient {
  /// Wait on a previously returned operation using a reader client. Returns the complete terminal operation.
  /// Timeout applies to polling after the initial mutation; timing out does not cancel the remote operation.
  public func waitForOperation(
    _ initial: Data, timeout: TimeInterval = 120, pollInterval: TimeInterval = 1
  ) async throws -> Data {
    try DocumentAIOperation.validateTiming(timeout: timeout, interval: pollInterval)
    guard capability == .reader else { throw DocumentAIError.invalidArgument("Explicit operation polling requires reader capability") }
    let initialOperation = try DocumentAIOperation.decode(initial)
    let method = initialOperation.name.contains("/locations/") ?
      "projects.locations.operations.get" : "projects.operations.get"
    // Validate even already-completed operations before returning their contents.
    _ = try request(method: method, parameters: ["name": [initialOperation.name]])
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(timeout))
    var current = initial
    while true {
      try Task.checkCancellation()
      let operation = try DocumentAIOperation.decode(current)
      guard operation.name == initialOperation.name else { throw DocumentAIError.transport }
      if operation.done == true {
        if let error = operation.error { throw DocumentAIError.operationFailed(code: error.code) }
        return current
      }
      guard operation.error == nil else { throw DocumentAIError.transport }
      let remaining = clock.now.duration(to: deadline)
      guard remaining > .zero else { throw DocumentAIError.operationTimeout }
      try await clock.sleep(for: min(.seconds(pollInterval), remaining))
      let available = clock.now.duration(to: deadline)
      guard available > .zero else { throw DocumentAIError.operationTimeout }
      let seconds = Double(available.components.seconds) + Double(available.components.attoseconds) / 1e18
      do {
        current = try await call(method: method, parameters: ["name": [operation.name]], requestTimeout: min(120, seconds))
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        if clock.now >= deadline { throw DocumentAIError.operationTimeout }
        throw error
      }
      guard clock.now < deadline else { throw DocumentAIError.operationTimeout }
    }
  }
}
