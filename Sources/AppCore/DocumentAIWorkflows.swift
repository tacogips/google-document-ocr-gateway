import Foundation

extension DocumentAIClient {
  /// Return complete raw pages, preserving metadata and unknown fields on every page.
  public func allPages(
    method id: String, parameters: [String: [String]] = [:], body: Data? = nil,
    maximumPages: Int = 10_000
  ) async throws -> [Data] {
    let method = try catalog.method(id)
    let bodyPagination = method.id.hasSuffix(".dataset.listDocuments")
    guard capability == .reader,
          bodyPagination || method.parameters?["pageToken"] != nil,
          maximumPages > 0, parameters["pageToken"] == nil else {
      throw DocumentAIError.invalidArgument("Pagination requires a paginated read, positive page limit, and no initial page token")
    }
    let originalBody = body ?? Data("{}".utf8)
    if bodyPagination { _ = try DocumentAIJSONBody.adding("pageToken", value: "", to: originalBody) }
    var nextParameters = parameters
    var nextBody = body
    var pages: [Data] = []
    var seen: Set<String> = []
    while true {
      try Task.checkCancellation()
      let page = try await call(method: id, parameters: nextParameters, body: nextBody)
      pages.append(page)
      guard let object = try JSONSerialization.jsonObject(with: page) as? [String: Any] else {
        throw DocumentAIError.transport
      }
      guard let rawToken = object["nextPageToken"] else { return pages }
      guard let token = rawToken as? String else { throw DocumentAIError.transport }
      if token.isEmpty { return pages }
      guard seen.insert(token).inserted, pages.count < maximumPages else {
        throw DocumentAIError.invalidArgument("Pagination repeated a token or exceeded the page limit")
      }
      if bodyPagination {
        nextBody = try DocumentAIJSONBody.adding("pageToken", value: token, to: originalBody)
      } else {
        nextParameters["pageToken"] = [token]
      }
    }
  }

  /// Process local bytes with all additional processing options supplied as JSON.
  public func processDocument(
    name: String, content: Data, mimeType: String, options: Data = Data("{}".utf8)
  ) async throws -> Data {
    let body = try Self.documentBody(content: content, mimeType: mimeType, options: options)
    let resource = name.contains("/processorVersions/") ? "processors.processorVersions" : "processors"
    return try await call(method: "projects.locations.\(resource).process", parameters: ["name": [name]], body: body)
  }

  public static func documentBody(content: Data, mimeType: String, options: Data = Data("{}".utf8)) throws -> Data {
    guard !content.isEmpty, !mimeType.isEmpty else {
      throw DocumentAIError.invalidArgument("Document bytes and MIME type must not be empty")
    }
    guard let object = (try? JSONSerialization.jsonObject(with: options)) as? [String: Any],
          object["inlineDocument"] == nil, object["gcsDocument"] == nil else {
      throw DocumentAIError.invalidArgument("Local document options cannot include another document source")
    }
    return try DocumentAIJSONBody.adding("rawDocument", value: [
      "content": content.base64EncodedString(), "mimeType": mimeType
    ], to: options)
  }
}

/// Add an absent top-level field without re-encoding any existing JSON values.
enum DocumentAIJSONBody {
  static func adding(_ key: String, value: Any, to data: Data) throws -> Data {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], object[key] == nil,
          let closing = data.lastIndex(of: UInt8(ascii: "}")) else {
      throw DocumentAIError.invalidArgument("Expected a JSON object without \(key)")
    }
    let field = try JSONSerialization.data(withJSONObject: [key: value], options: [.sortedKeys])
    var result = Data(data[..<closing])
    if !object.isEmpty { result.append(Data(",".utf8)) }
    result.append(field.dropFirst().dropLast())
    result.append(data[closing...])
    return result
  }
}
