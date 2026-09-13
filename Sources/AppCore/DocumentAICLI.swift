import Foundation

/// Shared CLI adapter. Success and error output is JSON except for help/version.
public struct DocumentAICLI: Sendable {
  public let arguments: [String]

  private let transport: any DocumentAIHTTPTransport
  private let injectedTokens: (any DocumentAIAccessTokenProvider)?

  public init(
    arguments: [String], transport: any DocumentAIHTTPTransport = DocumentAIURLSessionTransport(),
    tokens: (any DocumentAIAccessTokenProvider)? = nil
  ) {
    self.arguments = arguments
    self.transport = transport
    self.injectedTokens = tokens
  }

  public static let usage = """
  Usage: google-document-ocr <command> [options]
    methods [--api-version v1|v1beta3]        List every API method and its capability
    discovery [--api-version v1|v1beta3]      Print full API discovery JSON and schemas
    reader|writer|deleter METHOD [options]   Call a Document AI method

  METHOD is a discovery ID, e.g. projects.locations.processors.process.
  Options:
    --api-version VERSION    v1 (default) or v1beta3
    --location LOCATION      Regional endpoint (default: us); global for global endpoint
    --param NAME=VALUE       Path or query parameter; repeat for repeated query values
    --body FILE              JSON request file; '-' reads standard input
    --access-token-env NAME  Token variable (default: GOOGLE_DOCUMENT_OCR_ACCESS_TOKEN)
    --service-account-env NAME  Environment variable containing service-account JSON
    --all-pages             Return an array of complete pages for a paginated read
    --file FILE             Read local OCR input (process methods only)
    --mime-type TYPE        MIME type required with --file; --body supplies other options
    --wait                 Wait for a mutation or operations.get to finish
    --timeout SECONDS      Polling timeout (default: 120); requires --wait
    --poll-interval SECONDS Poll interval (default: 1); requires --wait
    --help, --version

  Example:
    google-document-ocr writer projects.locations.processors.process \\
      --location us --param name=projects/PROJECT/locations/us/processors/PROCESSOR \\
      --body request.json
  """

  public func run() async throws -> Data {
    guard let command = arguments.first else { return Data(Self.usage.utf8) }
    if arguments == ["--help"] || arguments == ["-h"] { return Data(Self.usage.utf8) }
    if arguments == ["--version"] { return Data(Version.current.utf8) }
    let capability = DocumentAICapability(rawValue: command)
    guard capability != nil || command == "methods" || command == "discovery" else {
      throw DocumentAIError.invalidArgument("Unknown command: \(command)")
    }
    let optionStart: Int
    let method: String?
    if capability != nil {
      guard arguments.count >= 2, !arguments[1].hasPrefix("-") else {
        throw DocumentAIError.invalidArgument("A discovery method ID is required")
      }
      method = arguments[1]
      optionStart = 2
    } else {
      method = nil
      optionStart = 1
    }
    var options: [String: String] = [:]
    var parameters: [String: [String]] = [:]
    var index = optionStart
    let allowed = capability == nil ? ["--api-version"] :
      ["--api-version", "--location", "--body", "--access-token-env", "--param", "--all-pages", "--file", "--mime-type", "--wait", "--timeout", "--poll-interval", "--service-account-env"]
    while index < arguments.count {
      let flag = arguments[index]
      if ["--all-pages", "--wait"].contains(flag), capability != nil {
        guard options[flag] == nil else { throw DocumentAIError.invalidArgument("Duplicate option: \(flag)") }
        options[flag] = "true"
        index += 1
        continue
      }
      guard allowed.contains(flag), index + 1 < arguments.count else {
        throw DocumentAIError.invalidArgument("Unknown option or missing value: \(flag)")
      }
      let value = arguments[index + 1]
      if flag == "--param" {
        guard let equals = value.firstIndex(of: "="), equals != value.startIndex else {
          throw DocumentAIError.invalidArgument("Expected --param NAME=VALUE")
        }
        parameters[String(value[..<equals]), default: []].append(String(value[value.index(after: equals)...]))
      } else {
        guard options[flag] == nil else { throw DocumentAIError.invalidArgument("Duplicate option: \(flag)") }
        options[flag] = value
      }
      index += 2
    }
    guard let version = DocumentAIVersion(rawValue: options["--api-version"] ?? "v1") else {
      throw DocumentAIError.invalidArgument("Unsupported API version")
    }
    let catalog = try DocumentAICatalog(version: version)
    if command == "discovery" { return catalog.discoveryJSON }
    if command == "methods" {
      let methods = catalog.methods.map { ["id": $0.id, "httpMethod": $0.httpMethod, "path": $0.path, "capability": $0.capability.rawValue] }
      return try JSONSerialization.data(withJSONObject: ["ok": true, "command": command, "data": methods], options: [.sortedKeys])
    }
    guard let capability, let method else { throw DocumentAIError.invalidArgument("Missing method") }
    var body: Data?
    if let file = options["--body"] {
      do {
        body = try file == "-" ? FileHandle.standardInput.readToEnd() : Data(contentsOf: URL(fileURLWithPath: file))
      } catch {
        throw DocumentAIError.invalidArgument("Cannot read request body file")
      }
    } else { body = nil }
    if let file = options["--file"] {
      guard method.hasSuffix(".process"), let mime = options["--mime-type"] else {
        throw DocumentAIError.invalidArgument("--file requires a process method and --mime-type")
      }
      let content: Data
      do { content = try Data(contentsOf: URL(fileURLWithPath: file)) } catch {
        throw DocumentAIError.invalidArgument("Cannot read document file")
      }
      body = try DocumentAIClient.documentBody(content: content, mimeType: mime, options: body ?? Data("{}".utf8))
    } else if options["--mime-type"] != nil {
      throw DocumentAIError.invalidArgument("--mime-type requires --file")
    }
    let client = try DocumentAIClient(
      version: version, capability: capability, location: options["--location"] ?? "us",
      transport: transport, tokens: try tokenProvider(options: options)
    )
    let result = try await execute(client: client, method: method, parameters: parameters, body: body, options: options)
    let encodedCommand = try JSONEncoder().encode("\(command) \(method)")
    var output = Data("{\"ok\":true,\"command\":".utf8)
    output.append(encodedCommand)
    output.append(Data(",\"data\":".utf8))
    output.append(result)
    output.append(Data("}".utf8))
    return output
  }

  private func tokenProvider(options: [String: String]) throws -> any DocumentAIAccessTokenProvider {
    if let injectedTokens {
      guard options["--access-token-env"] == nil, options["--service-account-env"] == nil else {
        throw DocumentAIError.invalidArgument("Injected credentials cannot be combined with credential flags")
      }
      return injectedTokens
    }
    if let variable = options["--service-account-env"] {
      guard options["--access-token-env"] == nil else {
        throw DocumentAIError.invalidArgument("Choose one credential source")
      }
      guard let json = ProcessInfo.processInfo.environment[variable] else {
        throw DocumentAIError.missingCredential(variable)
      }
      return try DocumentAIServiceAccountTokenProvider(credentialJSON: Data(json.utf8))
    }
    return DocumentAIEnvironmentTokenProvider(variable: options["--access-token-env"] ?? "GOOGLE_DOCUMENT_OCR_ACCESS_TOKEN")
  }

  private func execute(
    client: DocumentAIClient, method: String, parameters: [String: [String]],
    body: Data?, options: [String: String]
  ) async throws -> Data {
    if options["--wait"] == nil, options["--timeout"] != nil || options["--poll-interval"] != nil {
      throw DocumentAIError.invalidArgument("Polling options require --wait")
    }
    guard options["--wait"] == nil || options["--all-pages"] == nil else {
      throw DocumentAIError.invalidArgument("--wait cannot be combined with --all-pages")
    }
    let result: Data
    if options["--wait"] != nil {
      guard let timeout = Double(options["--timeout"] ?? "120"),
            let interval = Double(options["--poll-interval"] ?? "1") else {
        throw DocumentAIError.invalidArgument("Invalid polling duration")
      }
      try DocumentAIOperation.validateTiming(timeout: timeout, interval: interval)
      if client.capability == .reader {
        guard ["documentai.projects.locations.operations.get", "documentai.projects.operations.get"].contains(try client.catalog.method(method).id) else {
          throw DocumentAIError.invalidArgument("Reader --wait requires operations.get")
        }
        let initial = try await client.call(method: method, parameters: parameters, body: body)
        result = try await client.waitForOperation(initial, timeout: timeout, pollInterval: interval)
      } else {
        result = try await client.callAndWait(method: method, parameters: parameters, body: body, timeout: timeout, pollInterval: interval)
      }
    } else if options["--all-pages"] != nil {
      let pages = try await client.allPages(method: method, parameters: parameters, body: body)
      var joined = Data("[".utf8)
      for (index, page) in pages.enumerated() {
        if index > 0 { joined.append(Data(",".utf8)) }
        joined.append(page)
      }
      joined.append(Data("]".utf8))
      result = joined
    } else {
      result = try await client.call(method: method, parameters: parameters, body: body)
    }
    return result
  }

  public static func failure(_ error: any Error, command: String?) -> (data: Data, exitCode: Int32) {
    let code: String
    let message: String
    let exitCode: Int32
    switch error {
    case DocumentAIError.invalidArgument(let detail):
      (code, message, exitCode) = ("invalid_argument", detail, 2)
    case DocumentAIError.missingCredential(let variable):
      (code, message, exitCode) = ("authentication", "Missing or invalid credential: \(variable)", 3)
    case DocumentAIError.provider(let status, _):
      (code, message, exitCode) = ("provider", "Document AI returned HTTP \(status)", 4)
    case DocumentAIError.operationFailed(let status):
      (code, message, exitCode) = ("operation_failed", "Operation failed with code \(status)", 5)
    case DocumentAIError.operationTimeout:
      (code, message, exitCode) = ("operation_timeout", "Operation polling timed out", 6)
    case DocumentAIError.transport:
      (code, message, exitCode) = ("transport", "Document AI request failed", 4)
    default:
      (code, message, exitCode) = ("unexpected", "Command failed or was cancelled", 1)
    }
    var details: [String: Any] = ["code": code, "message": message]
    if case DocumentAIError.provider(let status, let body) = error {
      details["httpStatus"] = status
      if let provider = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
        details["provider"] = provider["error"]
      }
    }
    let object: [String: Any] = ["ok": false, "command": command ?? "", "error": details]
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{\"ok\":false}".utf8)
    return (data, exitCode)
  }
}
