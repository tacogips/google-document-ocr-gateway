import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AppCore

private struct WorkflowToken: DocumentAIAccessTokenProvider {
  func accessToken() async throws -> String { "test" }
}

private actor PageTransport: DocumentAIHTTPTransport {
  var requests: [URLRequest] = []
  let repeatToken: Bool

  init(repeatToken: Bool = false) { self.repeatToken = repeatToken }

  func send(_ request: URLRequest) async throws -> DocumentAIHTTPResponse {
    requests.append(request)
    let json = requests.count == 1 || repeatToken ?
      #"{"nextPageToken":"a&b=+", "items":[123456789012345678901]}"# : #"{"items":[]}"#
    return DocumentAIHTTPResponse(status: 200, body: Data(json.utf8))
  }
}

@Test func paginatesQueryAndBodyWithoutLosingNumbers() async throws {
  for bodyPagination in [false, true] {
    let transport = PageTransport()
    let client = try DocumentAIClient(version: .v1beta3, capability: .reader, transport: transport, tokens: WorkflowToken())
    let method = bodyPagination ? "projects.locations.processors.dataset.listDocuments" : "projects.locations.processors.list"
    let parameters = bodyPagination ? ["dataset": ["projects/p/locations/us/processors/p/dataset"]] : ["parent": ["projects/p/locations/us"]]
    let body = bodyPagination ? Data(#"{"futureNumber":123456789012345678901}"#.utf8) : nil
    let pages = try await client.allPages(method: method, parameters: parameters, body: body)
    #expect(pages.count == 2)
    #expect(String(data: pages[0], encoding: .utf8)?.contains("123456789012345678901") == true)
    let requests = await transport.requests
    #expect(requests.count == 2)
    if bodyPagination {
      let data = try #require(requests[1].httpBody)
      let text = try #require(String(data: data, encoding: .utf8))
      #expect(text.contains("123456789012345678901"))
      #expect(text.contains("a&b=+"))
    } else {
      let url = try #require(requests[1].url)
      #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "a&b=+")
    }
  }
}

@Test func paginationRejectsRepeatedToken() async throws {
  let transport = PageTransport(repeatToken: true)
  let client = try DocumentAIClient(capability: .reader, transport: transport, tokens: WorkflowToken())
  await #expect(throws: DocumentAIError.self) {
    try await client.allPages(method: "projects.locations.processors.list", parameters: ["parent": ["projects/p/locations/us"]])
  }
  #expect(await transport.requests.count == 2)
}

@Test func localDocumentBodyPreservesOptionsAndRejectsConflictingSources() throws {
  let options = Data(#"{"processOptions":{"ocrConfig":{"enableSymbol":true}},"number":123456789012345678901}"#.utf8)
  let body = try DocumentAIClient.documentBody(content: Data("abc".utf8), mimeType: "application/pdf", options: options)
  #expect(String(data: body, encoding: .utf8)?.contains("123456789012345678901") == true)
  let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
  #expect((object["rawDocument"] as? [String: String])?["content"] == "YWJj")
  for source in ["rawDocument", "inlineDocument", "gcsDocument"] {
    let options = Data("{\"\(source)\":{}}".utf8)
    #expect(throws: DocumentAIError.self) {
      try DocumentAIClient.documentBody(content: Data("abc".utf8), mimeType: "application/pdf", options: options)
    }
  }
}
