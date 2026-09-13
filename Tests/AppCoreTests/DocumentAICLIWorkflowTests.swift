import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AppCore

private struct WorkflowCLITokens: DocumentAIAccessTokenProvider {
  func accessToken() async throws -> String { "sensitive-token" }
}

private actor WorkflowCLITransport: DocumentAIHTTPTransport {
  var requests: [URLRequest] = []
  let responses: [DocumentAIHTTPResponse]
  init(_ responses: [DocumentAIHTTPResponse]) { self.responses = responses }
  func send(_ request: URLRequest) async throws -> DocumentAIHTTPResponse {
    requests.append(request)
    return responses[min(requests.count - 1, responses.count - 1)]
  }
}

private func response(_ json: String, status: Int = 200) -> DocumentAIHTTPResponse {
  DocumentAIHTTPResponse(status: status, body: Data(json.utf8))
}

@Test func cliLoadsDocumentAndOptionsFiles() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let document = directory.appendingPathComponent("document.pdf")
  let options = directory.appendingPathComponent("options.json")
  try Data("document fixture".utf8).write(to: document)
  try Data(#"{"processOptions":{"ocrConfig":{"enableSymbol":true}}}"#.utf8).write(to: options)
  let transport = WorkflowCLITransport([response(#"{"document":{"text":"recognized"}}"#)])
  let cli = DocumentAICLI(arguments: ["writer", "projects.locations.processors.process",
    "--param", "name=projects/p/locations/us/processors/p", "--file", document.path,
    "--mime-type", "application/pdf", "--body", options.path], transport: transport, tokens: WorkflowCLITokens())
  let output = try await cli.run()
  #expect(String(data: output, encoding: .utf8)?.contains("recognized") == true)
  let requests = await transport.requests
  let body = try #require(requests.first?.httpBody)
  let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
  #expect((json["rawDocument"] as? [String: String])?["content"] == Data("document fixture".utf8).base64EncodedString())
  #expect(json["processOptions"] != nil)
}

@Test func cliPaginationReturnsCompletePages() async throws {
  let transport = WorkflowCLITransport([response(#"{"processors":[],"nextPageToken":"next+"}"#), response(#"{"processors":[{"name":"p"}]}"#)])
  let cli = DocumentAICLI(arguments: ["reader", "projects.locations.processors.list", "--param",
    "parent=projects/p/locations/us", "--all-pages"], transport: transport, tokens: WorkflowCLITokens())
  let output = try await cli.run()
  let json = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
  #expect((json["data"] as? [[String: Any]])?.count == 2)
  let requests = await transport.requests
  #expect(requests.count == 2)
  #expect(requests[1].url?.absoluteString.contains("next%2B") == true)
}

@Test func cliWaitReturnsTerminalOperation() async throws {
  let name = "projects/p/locations/us/operations/o"
  let transport = WorkflowCLITransport([response("{\"name\":\"\(name)\"}"), response("{\"name\":\"\(name)\",\"done\":true,\"response\":{}}")])
  let cli = DocumentAICLI(arguments: ["writer", "projects.locations.processors.batchProcess", "--param",
    "name=projects/p/locations/us/processors/p", "--wait", "--poll-interval", "0.001", "--timeout", "5"],
    transport: transport, tokens: WorkflowCLITokens())
  let output = try await cli.run()
  #expect(String(data: output, encoding: .utf8)?.contains("\"done\":true") == true)
  #expect(await transport.requests.map(\.httpMethod) == ["POST", "GET"])
}

@Test func providerDiagnosticsPreserveUsefulDetailsAndRedactCredentials() async throws {
  let errorJSON = """
  {"error":{"code":403,"status":"PERMISSION_DENIED","message":"Denied sensitive-token",
  "details":[{"reason":"IAM_PERMISSION_DENIED","metadata":{"access_token":"other-secret",
  "permission":"documentai.processors.processOnline","authorization":"Bearer hidden"}}]}}
  """
  let transport = WorkflowCLITransport([response(errorJSON, status: 403)])
  let cli = DocumentAICLI(arguments: ["reader", "projects.locations.get", "--param", "name=projects/p/locations/us"],
    transport: transport, tokens: WorkflowCLITokens())
  do {
    _ = try await cli.run()
    Issue.record("Expected failure")
  } catch {
    let failure = DocumentAICLI.failure(error, command: "reader")
    let text = try #require(String(data: failure.data, encoding: .utf8))
    #expect(failure.exitCode == 4)
    #expect(text.contains("PERMISSION_DENIED"))
    #expect(text.contains("documentai.processors.processOnline"))
    for secret in ["sensitive-token", "other-secret", "Bearer hidden"] { #expect(!text.contains(secret)) }
  }
}

@Test func malformedOCROptionsAreArgumentErrors() throws {
  #expect(throws: DocumentAIError.self) {
    try DocumentAIClient.documentBody(content: Data("file".utf8), mimeType: "application/pdf", options: Data("invalid".utf8))
  }
}
