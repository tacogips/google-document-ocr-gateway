import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A capability-scoped client covering every method in the bundled Google API discovery document.
public struct DocumentAIClient: Sendable {
  public let catalog: DocumentAICatalog
  public let capability: DocumentAICapability
  public let location: String
  private let transport: any DocumentAIHTTPTransport
  private let tokens: any DocumentAIAccessTokenProvider

  public init(
    version: DocumentAIVersion = .v1,
    capability: DocumentAICapability,
    location: String = "us",
    transport: any DocumentAIHTTPTransport = DocumentAIURLSessionTransport(),
    tokens: any DocumentAIAccessTokenProvider = DocumentAIEnvironmentTokenProvider()
  ) throws {
    guard location.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil,
          location.count <= 63 else {
      throw DocumentAIError.invalidArgument("Invalid location")
    }
    catalog = try DocumentAICatalog(version: version)
    self.capability = capability
    self.location = location
    self.transport = transport
    self.tokens = tokens
  }

  /// Construct a validated request without reading credentials or performing network I/O.
  public func request(
    method id: String, parameters: [String: [String]] = [:], body: Data? = nil
  ) throws -> URLRequest {
    let method = try catalog.method(id)
    guard method.capability == capability else {
      throw DocumentAIError.invalidArgument("Method requires \(method.capability.rawValue) capability")
    }
    let definitions = catalog.globalParameters.merging(method.parameters ?? [:]) { _, method in method }
    var path = method.path
    var query: [URLQueryItem] = []
    for (name, definition) in definitions where definition.required == true {
      guard let values = parameters[name], !values.isEmpty else {
        throw DocumentAIError.invalidArgument("Missing required parameter: \(name)")
      }
    }
    for name in parameters.keys.sorted() {
      guard let definition = definitions[name], let values = parameters[name], !values.isEmpty else {
        throw DocumentAIError.invalidArgument("Unknown or empty parameter: \(name)")
      }
      guard definition.repeated == true || values.count == 1 else {
        throw DocumentAIError.invalidArgument("Parameter is not repeated: \(name)")
      }
      // Credentials are supplied only through the token provider. Keep responses in JSON format.
      guard !["access_token", "oauth_token", "key"].contains(name),
            name != "alt" || values == ["json"] else {
        throw DocumentAIError.invalidArgument("Unsupported parameter: \(name)")
      }
      if definition.location == "path" {
        let value = values[0]
        try validateResource(value, pattern: definition.pattern, parameter: name)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
          throw DocumentAIError.invalidArgument("Invalid resource parameter: \(name)")
        }
        path = path.replacingOccurrences(of: "{+\(name)}", with: encoded)
        path = path.replacingOccurrences(of: "{\(name)}", with: encoded)
      } else {
        for value in values { query.append(URLQueryItem(name: name, value: value)) }
      }
    }
    guard !path.contains("{") else { throw DocumentAIError.invalidArgument("Missing resource parameter") }
    if let body {
      guard method.request != nil,
            (try? JSONSerialization.jsonObject(with: body)) is [String: Any] else {
        throw DocumentAIError.invalidArgument("Method body must be a JSON object supported by this method")
      }
    }
    let host = location == "global" ? "documentai.googleapis.com" : "\(location)-documentai.googleapis.com"
    guard var components = URLComponents(string: "https://\(host)/\(path)") else {
      throw DocumentAIError.invalidArgument("Invalid request URL")
    }
    if !query.isEmpty {
      components.queryItems = query
      components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    }
    guard let url = components.url else { throw DocumentAIError.invalidArgument("Invalid request URL") }
    var request = URLRequest(url: url)
    request.httpMethod = method.httpMethod
    request.httpBody = body ?? (method.request == nil ? nil : Data("{}".utf8))
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if request.httpBody != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    request.timeoutInterval = 120
    return request
  }

  /// Execute any catalog method. Raw JSON preserves all provider fields and numeric lexemes.
  public func call(
    method: String, parameters: [String: [String]] = [:], body: Data? = nil,
    requestTimeout: TimeInterval = 120
  ) async throws -> Data {
    guard requestTimeout.isFinite, requestTimeout > 0 else {
      throw DocumentAIError.invalidArgument("Request timeout must be positive and finite")
    }
    var request = try request(method: method, parameters: parameters, body: body)
    request.timeoutInterval = requestTimeout
    let token = try await tokens.accessToken()
    guard !token.isEmpty, token.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
      throw DocumentAIError.missingCredential("Token provider returned an invalid token")
    }
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let response: DocumentAIHTTPResponse
    do {
      response = try await transport.send(request)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      // Transport diagnostics may include the request or credentials.
      throw DocumentAIError.transport
    }
    guard (200..<300).contains(response.status) else {
      let diagnostic = DocumentAIDiagnostics.sanitize(response.body, tokens: [token])
      throw DocumentAIError.provider(status: response.status, body: diagnostic)
    }
    if response.body.isEmpty { return Data("{}".utf8) }
    guard (try? JSONSerialization.jsonObject(with: response.body)) != nil else {
      throw DocumentAIError.transport
    }
    return response.body
  }

  private func validateResource(_ value: String, pattern: String?, parameter: String) throws {
    let segments = value.split(separator: "/", omittingEmptySubsequences: false)
    guard !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
          !value.contains("%"), !value.contains("?"), !value.contains("#"), !value.contains("\\"),
          value.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value != 127 }) else {
      throw DocumentAIError.invalidArgument("Invalid resource parameter: \(parameter)")
    }
    if let pattern, value.range(of: pattern, options: .regularExpression) == nil {
      throw DocumentAIError.invalidArgument("Resource does not match \(parameter) pattern")
    }
    if let index = segments.firstIndex(of: "locations"), index + 1 < segments.count {
      guard segments[index + 1] == Substring(location) else {
        throw DocumentAIError.invalidArgument("Resource location differs from endpoint location")
      }
    }
  }
}

extension DocumentAIClient {
  /// Invoke an operation-returning mutation once, then poll only the returned operation.
  public func callAndWait(
    method: String, parameters: [String: [String]] = [:], body: Data? = nil,
    timeout: TimeInterval = 120, pollInterval: TimeInterval = 1
  ) async throws -> Data {
    try DocumentAIOperation.validateTiming(timeout: timeout, interval: pollInterval)
    guard capability != .reader,
          try catalog.method(method).response?["$ref"] == "GoogleLongrunningOperation" else {
      throw DocumentAIError.invalidArgument("Waiting requires an operation-returning mutation")
    }
    let operation = try await call(method: method, parameters: parameters, body: body)
    let reader = try DocumentAIClient(
      version: catalog.version, capability: .reader, location: location, transport: transport, tokens: tokens
    )
    return try await reader.waitForOperation(operation, timeout: timeout, pollInterval: pollInterval)
  }
}
