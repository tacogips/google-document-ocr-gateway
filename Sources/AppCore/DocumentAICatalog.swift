import Foundation

public enum DocumentAIVersion: String, Codable, CaseIterable, Sendable {
  case v1, v1beta3
}

public enum DocumentAICapability: String, Codable, CaseIterable, Sendable {
  case reader, writer, deleter
}

public enum DocumentAIError: Error, Equatable, Sendable {
  case invalidArgument(String)
  case missingCredential(String)
  case operationFailed(code: Int)
  case operationTimeout
  case transport
  case provider(status: Int, body: Data)
}

/// Google's complete method metadata; request and response schemas are in the catalog snapshot.
public struct DocumentAIMethod: Decodable, Sendable {
  public struct Parameter: Decodable, Sendable {
    public let location: String
    public let required: Bool?
    public let repeated: Bool?
    public let type: String
    public let pattern: String?
  }

  public let id: String
  public let httpMethod: String
  public let path: String
  public let description: String?
  public let parameters: [String: Parameter]?
  public let request: [String: String]?
  public let response: [String: String]?

  public var capability: DocumentAICapability {
    if httpMethod == "DELETE" || id.hasSuffix(".batchDeleteDocuments") { return .deleter }
    if httpMethod == "GET" || id.hasSuffix(".listDocuments") { return .reader }
    return .writer
  }
}

public struct DocumentAICatalog: Sendable {
  private struct Resource: Decodable {
    let methods: [String: DocumentAIMethod]?
    let resources: [String: Resource]?

    var flattened: [DocumentAIMethod] {
      Array((methods ?? [:]).values) + (resources ?? [:]).values.flatMap(\.flattened)
    }
  }

  public let version: DocumentAIVersion
  public let methods: [DocumentAIMethod]
  /// Unmodified discovery JSON, including every request and response schema.
  public let discoveryJSON: Data
  public let globalParameters: [String: DocumentAIMethod.Parameter]

  public init(version: DocumentAIVersion = .v1) throws {
    self.version = version
    let installedBundle: Bundle?
    if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
      let directory = executable.deletingLastPathComponent()
      installedBundle = Bundle(url: directory.appendingPathComponent("google-document-ocr-gateway_AppCore.bundle"))
        ?? Bundle(url: directory.appendingPathComponent("google-document-ocr-gateway_AppCore.resources"))
    } else { installedBundle = nil }
    let resources = installedBundle ?? Bundle.module
    guard let url = resources.url(
      forResource: "documentai-\(version.rawValue)", withExtension: "json", subdirectory: "Resources"
    ) else { throw DocumentAIError.invalidArgument("Missing bundled API discovery document") }
    discoveryJSON = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    methods = try decoder.decode(Resource.self, from: discoveryJSON).flattened.sorted { $0.id < $1.id }
    struct Root: Decodable { let parameters: [String: DocumentAIMethod.Parameter] }
    globalParameters = try decoder.decode(Root.self, from: discoveryJSON).parameters
  }

  public func method(_ id: String) throws -> DocumentAIMethod {
    let fullID = id.hasPrefix("documentai.") ? id : "documentai.\(id)"
    guard let method = methods.first(where: { $0.id == fullID }) else {
      throw DocumentAIError.invalidArgument("Unknown \(version.rawValue) method: \(id)")
    }
    return method
  }
}
