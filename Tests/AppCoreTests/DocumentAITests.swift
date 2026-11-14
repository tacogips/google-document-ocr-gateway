import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AppCore

@Test func discoveryCoverage() throws {
  for version in DocumentAIVersion.allCases {
    let catalog = try DocumentAICatalog(version: version)
    #expect(catalog.methods.count == (version == .v1 ? 42 : 48))
    #expect(Set(catalog.methods.map(\.id)).count == catalog.methods.count)
    #expect(try catalog.method("projects.locations.processors.process").capability == .writer)
    #expect(try catalog.method("projects.locations.processors.delete").capability == .deleter)
  }
  let beta = try DocumentAICatalog(version: .v1beta3)
  #expect(try beta.method("projects.locations.processors.dataset.listDocuments").capability == .reader)
  #expect(try beta.method("projects.locations.processors.dataset.batchDeleteDocuments").capability == .deleter)
}

@Test func constructsOCRRequestWithoutChangingBody() throws {
  let client = try DocumentAIClient(capability: .writer, location: "eu")
  let body = Data(#"{"rawDocument":{"content":"YWJj","mimeType":"application/pdf"},"processOptions":{"ocrConfig":{"enableSymbol":true}},"futureField":123456789012345678901}"#.utf8)
  let request = try client.request(method: "projects.locations.processors.process", parameters: [
    "name": ["projects/test/locations/eu/processors/123"]
  ], body: body)
  #expect(request.url?.absoluteString == "https://eu-documentai.googleapis.com/v1/projects/test/locations/eu/processors/123:process")
  #expect(request.httpMethod == "POST")
  #expect(request.httpBody == body)
  #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func rejectsCrossRegionAndInvalidResources() throws {
  let client = try DocumentAIClient(capability: .reader)
  for resource in ["projects/p/locations/eu/processors/x", "projects/p/locations/us/processors/..", "projects/p/locations/us/processors/%2e%2e"] {
    #expect(throws: DocumentAIError.self) {
      try client.request(method: "projects.locations.processors.get", parameters: ["name": [resource]])
    }
  }
  #expect(throws: DocumentAIError.self) {
    try client.request(method: "projects.locations.processors.delete", parameters: ["name": ["projects/p/locations/us/processors/x"]])
  }
}

@Test func constructsQueryWithoutInjection() throws {
  let client = try DocumentAIClient(capability: .reader)
  let request = try client.request(method: "projects.locations.processors.list", parameters: [
    "parent": ["projects/p/locations/us"], "pageToken": ["a&key=secret+#/="], "pageSize": ["20"]
  ])
  let url = try #require(request.url)
  let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
  #expect(components.queryItems?.first(where: { $0.name == "pageToken" })?.value == "a&key=secret+#/=")
  #expect(components.queryItems?.count == 2)
  #expect(components.percentEncodedQuery?.contains("%2B") == true)
  #expect(components.percentEncodedQuery?.contains("+") == false)
}

private struct FixtureTokens: DocumentAIAccessTokenProvider {
  func accessToken() async throws -> String { "fixture-token" }
}

private struct FixtureTransport: DocumentAIHTTPTransport {
  let status: Int
  let body: Data

  func send(_ request: URLRequest) async throws -> DocumentAIHTTPResponse {
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
    return DocumentAIHTTPResponse(status: status, body: body)
  }
}

@Test func preservesProviderJSONAndSanitizesFailures() async throws {
  let body = Data(#"{"text":"OCR","number":123456789012345678901234567890}"#.utf8)
  let client = try DocumentAIClient(capability: .reader, transport: FixtureTransport(status: 200, body: body), tokens: FixtureTokens())
  let result = try await client.call(method: "projects.locations.get", parameters: ["name": ["projects/p/locations/us"]])
  #expect(result == body)
  let failing = try DocumentAIClient(capability: .reader, transport: FixtureTransport(status: 403, body: Data("fixture-token".utf8)), tokens: FixtureTokens())
  do {
    _ = try await failing.call(method: "projects.locations.get", parameters: ["name": ["projects/p/locations/us"]])
    Issue.record("Expected provider failure")
  } catch {
    let failure = DocumentAICLI.failure(error, command: "reader")
    #expect(failure.exitCode == 4)
    #expect(String(data: failure.data, encoding: .utf8)?.contains("fixture-token") == false)
  }
}

@Test func offlineCLI() async throws {
  for version in DocumentAIVersion.allCases {
    let result = try await DocumentAICLI(arguments: ["methods", "--api-version", version.rawValue]).run()
    let object = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
    #expect((object["data"] as? [[String: String]])?.count == (version == .v1 ? 42 : 48))
  }
}

@Test func everyDiscoveredRouteConstructsAndEnforcesCapabilities() throws {
  for version in DocumentAIVersion.allCases {
    let catalog = try DocumentAICatalog(version: version)
    for method in catalog.methods {
      var parameters: [String: [String]] = [:]
      for (name, definition) in method.parameters ?? [:] where definition.location == "path" {
        let pattern = try #require(definition.pattern)
        let resource = pattern
          .replacingOccurrences(of: "[^/]+", with: "fixture")
          .replacingOccurrences(of: "^", with: "")
          .replacingOccurrences(of: "$", with: "")
          .replacingOccurrences(of: ".*", with: "fixture")
          .replacingOccurrences(of: "locations/fixture", with: "locations/us")
        parameters[name] = [resource]
      }
      for capability in DocumentAICapability.allCases {
        let client = try DocumentAIClient(version: version, capability: capability)
        if capability == method.capability {
          let request = try client.request(method: method.id, parameters: parameters)
          #expect(request.httpMethod == method.httpMethod)
          #expect(request.url?.host == "us-documentai.googleapis.com")
          #expect(request.url?.path.hasPrefix("/\(version.rawValue)/") == true)
          #expect(request.url?.absoluteString.contains("{") == false)
        } else {
          #expect(throws: DocumentAIError.self) {
            try client.request(method: method.id, parameters: parameters)
          }
        }
      }
    }
  }
}
