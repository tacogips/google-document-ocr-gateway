import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AppCore

private struct CoverageToken: DocumentAIAccessTokenProvider {
  func accessToken() async throws -> String { "cli-fixture" }
}

private actor CoverageTransport: DocumentAIHTTPTransport {
  var requests: [URLRequest] = []
  func send(_ request: URLRequest) async throws -> DocumentAIHTTPResponse {
    requests.append(request)
    return DocumentAIHTTPResponse(status: 200, body: Data(#"{"opaque":123456789012345678901234567890}"#.utf8))
  }
}

@Test func everyMethodExecutesThroughCLIWithAllQueryParameters() async throws {
  for version in DocumentAIVersion.allCases {
    let catalog = try DocumentAICatalog(version: version)
    for method in catalog.methods {
      let transport = CoverageTransport()
      var arguments = [method.capability.rawValue, method.id, "--api-version", version.rawValue]
      var expectedPath = method.path
      var expectedQuery: [String: [String]] = [:]
      for (name, parameter) in (method.parameters ?? [:]).sorted(by: { $0.key < $1.key }) {
        let value: String
        if parameter.location == "path" {
          value = try #require(parameter.pattern)
            .replacingOccurrences(of: "[^/]+", with: "fixture")
            .replacingOccurrences(of: ".*", with: "fixture")
            .replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "locations/fixture", with: "locations/us")
          expectedPath = expectedPath.replacingOccurrences(of: "{+\(name)}", with: value)
        } else {
          value = parameter.type == "boolean" ? "true" : parameter.type == "integer" ? "1" : "opaque & +/= value"
          expectedQuery[name] = [value]
        }
        arguments += ["--param", "\(name)=\(value)"]
        if parameter.repeated == true {
          arguments += ["--param", "\(name)=\(value)"]
          expectedQuery[name]?.append(value)
        }
      }
      let cli = DocumentAICLI(arguments: arguments, transport: transport, tokens: CoverageToken())
      let output = try await cli.run()
      let envelope = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
      #expect(envelope["ok"] as? Bool == true)
      #expect(envelope["command"] as? String == "\(method.capability.rawValue) \(method.id)")
      #expect(String(data: output, encoding: .utf8)?.contains("123456789012345678901234567890") == true)
      let requests = await transport.requests
      #expect(requests.count == 1)
      let request = try #require(requests.first)
      #expect(request.httpMethod == method.httpMethod)
      #expect(request.url?.path == "/\(expectedPath)")
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer cli-fixture")
      let url = try #require(request.url)
      let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
      for (name, values) in expectedQuery {
        #expect(components.queryItems?.filter { $0.name == name }.compactMap(\.value) == values)
      }
    }
  }
}

@Test func cliRejectsConflictingWorkflowsBeforeHTTP() async throws {
  for suffix in [["--wait", "--all-pages"], ["--timeout", "10"], ["--wait", "--timeout", "nan"]] {
    let transport = CoverageTransport()
    let cli = DocumentAICLI(arguments: ["writer", "projects.locations.processors.batchProcess",
      "--param", "name=projects/p/locations/us/processors/p"] + suffix, transport: transport, tokens: CoverageToken())
    await #expect(throws: DocumentAIError.self) { try await cli.run() }
    #expect(await transport.requests.isEmpty)
  }
}
