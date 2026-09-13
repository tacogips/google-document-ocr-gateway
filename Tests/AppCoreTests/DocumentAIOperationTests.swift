import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AppCore

private let operationName = "projects/p/locations/us/operations/123"

private struct OperationToken: DocumentAIAccessTokenProvider {
  func accessToken() async throws -> String { "test" }
}

private actor OperationTransport: DocumentAIHTTPTransport {
  var requests: [URLRequest] = []
  let replies: [Data]

  init(_ replies: [String]) { self.replies = replies.map { Data($0.utf8) } }

  func send(_ request: URLRequest) async throws -> DocumentAIHTTPResponse {
    requests.append(request)
    let index = min(requests.count - 1, replies.count - 1)
    return DocumentAIHTTPResponse(status: 200, body: replies[index])
  }
}

@Test func mutationWaitSubmitsOnceAndPreservesTerminalJSON() async throws {
  let terminal = "{\"name\":\"\(operationName)\",\"done\":true,\"response\":{\"large\":123456789012345678901}}"
  let transport = OperationTransport(["{\"name\":\"\(operationName)\"}", terminal])
  let client = try DocumentAIClient(capability: .writer, transport: transport, tokens: OperationToken())
  let result = try await client.callAndWait(method: "projects.locations.processors.batchProcess", parameters: [
    "name": ["projects/p/locations/us/processors/p"]
  ], timeout: 2, pollInterval: 0.001)
  #expect(result == Data(terminal.utf8))
  let requests = await transport.requests
  #expect(requests.map(\.httpMethod) == ["POST", "GET"])
  #expect(requests[1].url?.path == "/v1/\(operationName)")
  #expect(requests[1].timeoutInterval <= 2)
}

@Test func terminalFailureAndTimeoutHaveDistinctExitCodes() async throws {
  let client = try DocumentAIClient(capability: .reader)
  let failed = Data("{\"name\":\"\(operationName)\",\"done\":true,\"error\":{\"code\":7,\"message\":\"sensitive\"}}".utf8)
  do {
    _ = try await client.waitForOperation(failed)
    Issue.record("Expected failure")
  } catch {
    #expect(error as? DocumentAIError == .operationFailed(code: 7))
    #expect(DocumentAICLI.failure(error, command: "reader").exitCode == 5)
  }
  let pending = Data("{\"name\":\"\(operationName)\"}".utf8)
  do {
    _ = try await client.waitForOperation(pending, timeout: 0.001, pollInterval: 1)
    Issue.record("Expected timeout")
  } catch {
    #expect(error as? DocumentAIError == .operationTimeout)
    #expect(DocumentAICLI.failure(error, command: "reader").exitCode == 6)
  }
}

@Test func rejectsOperationNameChangesAndInvalidTiming() async throws {
  let transport = OperationTransport(["{\"name\":\"projects/p/locations/us/operations/other\",\"done\":true}"])
  let client = try DocumentAIClient(capability: .reader, transport: transport, tokens: OperationToken())
  let pending = Data("{\"name\":\"\(operationName)\"}".utf8)
  await #expect(throws: DocumentAIError.transport) {
    try await client.waitForOperation(pending, timeout: 2, pollInterval: 0.001)
  }
  for timeout in [0, -1, Double.infinity, Double.nan] {
    await #expect(throws: DocumentAIError.self) {
      try await client.waitForOperation(pending, timeout: timeout)
    }
  }
}

@Test func waitingRejectsNonOperationMutationBeforeSubmission() async throws {
  let transport = OperationTransport(["{}"])
  let client = try DocumentAIClient(capability: .writer, transport: transport, tokens: OperationToken())
  await #expect(throws: DocumentAIError.self) {
    try await client.callAndWait(method: "projects.locations.processors.process")
  }
  #expect(await transport.requests.isEmpty)
}
