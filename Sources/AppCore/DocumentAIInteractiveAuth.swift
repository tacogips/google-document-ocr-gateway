import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GoogleServiceGatewayCore

public struct DocumentAIInteractiveAuth: Sendable {
  public static let scope = "https://www.googleapis.com/auth/cloud-platform"
  private let transport: any DocumentAIHTTPTransport
  private let authorizer: any InteractiveOAuthAuthorizer

  public init(transport: any DocumentAIHTTPTransport = DocumentAIURLSessionTransport(),
              authorizer: any InteractiveOAuthAuthorizer = LoopbackOAuthAuthorizer(prefix: "GOOGLE_DOCUMENT_OCR_GATEWAY_")) {
    self.transport = transport; self.authorizer = authorizer
  }

  public func run(arguments: [String], environment: [String: String]) async throws -> Data {
    guard let command = arguments.first, ["login", "status", "revoke"].contains(command) else {
      throw DocumentAIError.invalidArgument("auth requires login, status, or revoke")
    }
    var flags: [String: String] = [:]
    var index = 1
    let allowed = ["--credential", "--confirm-credential", "--open-browser", "--timeout-seconds"]
    while index < arguments.count {
      let key = arguments[index]
      guard allowed.contains(key), flags[key] == nil, index + 1 < arguments.count else {
        throw DocumentAIError.invalidArgument("Invalid auth options")
      }
      flags[key] = arguments[index + 1]; index += 2
    }
    let id = flags["--credential"] ?? "google-personal"
    guard id.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil else {
      throw DocumentAIError.invalidArgument("Invalid credential ID")
    }
    let selected = credentialEnvironment(id: id, environment: environment)
    let url = tokenURL(id: id, environment: selected)
    if command == "status" {
      let raw = selected["GOOGLE_DOCUMENT_OCR_GATEWAY_ACCESS_TOKEN"]
      let inline = selected["GOOGLE_DOCUMENT_OCR_GATEWAY_TOKEN_STORE_JSON"]
      let external = raw != nil || inline != nil
      let token: DocumentAIOAuthTokenStore?
      if let inline {
        token = try? DocumentAIExternalCredentials.decodeTokenStore(Data(inline.utf8))
      } else if raw != nil { token = nil
      } else { token = try? DocumentAIOAuthStorage.read(url) }
      let state: String
      if let raw {
        state = (try? DocumentAIStaticTokenProvider(token: raw)) == nil ? "INVALID" : "READY"
      } else if let token {
        if token.tokenType.caseInsensitiveCompare("Bearer") != .orderedSame
            || (try? DocumentAIStaticTokenProvider(token: token.accessToken)) == nil { state = "INVALID"
        } else { state = token.expiresAt > Date().addingTimeInterval(60) ? "READY" : "EXPIRED" }
      } else { state = inline != nil || FileManager.default.fileExists(atPath: url.path) ? "INVALID" : "MISSING" }
      return try JSONSerialization.data(withJSONObject: [
        "ok": true, "credential": id, "state": state,
        "tokenSource": inline != nil ? "ENVIRONMENT_JSON" : (external ? "ENVIRONMENT_TOKEN" : "FILE"), "hasRefreshToken": token?.refreshToken != nil,
        "tokenStorePath": external ? NSNull() : url.path as Any
      ], options: [.sortedKeys])
    }
    guard selected["GOOGLE_DOCUMENT_OCR_GATEWAY_ACCESS_TOKEN"] == nil,
          selected["GOOGLE_DOCUMENT_OCR_GATEWAY_TOKEN_STORE_JSON"] == nil else {
      throw DocumentAIError.invalidArgument("Environment tokens are immutable; remove the override before auth login/revoke")
    }
    if command == "revoke" {
      guard flags["--credential"] != nil, flags["--confirm-credential"] == id else {
        throw DocumentAIError.invalidArgument("Revoke requires --credential and an exact --confirm-credential")
      }
      let token = try DocumentAIOAuthStorage.read(url)
      do { try await oauth.revoke(sharedToken(token)) } catch { throw DocumentAIError.missingCredential("Google OAuth revocation failed") }
      try DocumentAIOAuthStorage.remove(url)
      return try JSONSerialization.data(withJSONObject: ["ok": true, "credential": id, "revoked": true])
    }
    if let text = flags["--timeout-seconds"], TimeInterval(text) == nil {
      throw DocumentAIError.invalidArgument("--timeout-seconds must be numeric")
    }
    let timeout = flags["--timeout-seconds"].flatMap(TimeInterval.init) ?? 180
    guard timeout.isFinite, timeout > 0, timeout <= 600 else {
      throw DocumentAIError.invalidArgument("--timeout-seconds must be between 1 and 600")
    }
    let openBrowser: Bool
    switch flags["--open-browser"] ?? "true" {
    case "true": openBrowser = true
    case "false": openBrowser = false
    default: throw DocumentAIError.invalidArgument("--open-browser must be true or false")
    }
    let client = try applicationClient(environment: selected)
    if let clientPath = selected["GOOGLE_DOCUMENT_OCR_GATEWAY_OAUTH_CLIENT_PATH"],
       URL(fileURLWithPath: clientPath).standardizedFileURL == url.standardizedFileURL {
      throw DocumentAIError.invalidArgument("OAuth client and token-store paths must differ")
    }
    if FileManager.default.fileExists(atPath: url.path) {
      let existing = try DocumentAIOAuthStorage.read(url)
      guard Set(existing.scopes) == [Self.scope] else { throw DocumentAIError.missingCredential("Existing credential scope is invalid") }
    }
    let token: OAuthTokenCredential
    do {
      token = try await GoogleOAuthBrowserLogin(oauth: oauth, authorizer: authorizer).login(
        client: client, scopes: [Self.scope], openBrowser: openBrowser, timeout: timeout)
    } catch { throw DocumentAIError.missingCredential("Google browser authorization failed") }
    let store = DocumentAIOAuthTokenStore(accessToken: token.accessToken, refreshToken: token.refreshToken,
                                        tokenType: token.tokenType, scopes: token.scopes, expiresAt: token.expiresAt)
    try DocumentAIOAuthStorage.write(store, to: url)
    return try JSONSerialization.data(withJSONObject: ["ok": true, "credential": id, "state": "READY", "tokenStorePath": url.path])
  }

  func applicationClient(environment: [String: String]) throws -> OAuthClientConfiguration {
    let json = environment["GOOGLE_DOCUMENT_OCR_GATEWAY_OAUTH_CLIENT_JSON"]
    let path = environment["GOOGLE_DOCUMENT_OCR_GATEWAY_OAUTH_CLIENT_PATH"]
    guard json == nil || path == nil else { throw DocumentAIError.invalidArgument("Select OAuth client JSON or path") }
    guard let input = json ?? path else {
      throw DocumentAIError.missingCredential("A registered OAuth application client is required")
    }
    do {
      return try OAuthClientConfiguration.imported(from: DocumentAIExternalCredentials.data(input, isPath: json == nil))
    } catch { throw DocumentAIError.missingCredential("Installed OAuth application JSON is invalid") }
  }

  func credentialEnvironment(id: String, environment: [String: String]) -> [String: String] {
    var selected = environment
    let prefix = "GOOGLE_DOCUMENT_OCR_GATEWAY_CREDENTIAL_" + id.uppercased().replacingOccurrences(of: "-", with: "_") + "_"
    let groups = [["ACCESS_TOKEN", "TOKEN_STORE_JSON", "TOKEN_STORE_PATH", "SERVICE_ACCOUNT_JSON", "SERVICE_ACCOUNT_PATH"],
                  ["OAUTH_CLIENT_JSON", "OAUTH_CLIENT_PATH"]]
    for suffixes in groups {
      if suffixes.contains(where: { environment[prefix + $0] != nil }) {
        for suffix in suffixes { selected.removeValue(forKey: "GOOGLE_DOCUMENT_OCR_GATEWAY_" + suffix) }
      }
      for suffix in suffixes {
        if let value = environment[prefix + suffix] { selected["GOOGLE_DOCUMENT_OCR_GATEWAY_" + suffix] = value }
      }
    }
    return selected
  }

  func tokenURL(id: String = "google-personal", environment: [String: String]) -> URL {
    if let path = environment["GOOGLE_DOCUMENT_OCR_GATEWAY_TOKEN_STORE_PATH"] { return URL(fileURLWithPath: path) }
    let root = environment["XDG_STATE_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state").path
    return URL(fileURLWithPath: root).appendingPathComponent("google-document-ocr-gateway/credentials/\(id).json")
  }

  var oauth: GoogleOAuthClient { GoogleOAuthClient(transport: DocumentAIOAuthTransport(transport: transport)) }
  func sharedToken(_ token: DocumentAIOAuthTokenStore) -> OAuthTokenCredential {
    OAuthTokenCredential(accessToken: token.accessToken, refreshToken: token.refreshToken, tokenType: token.tokenType,
                         scopes: token.scopes, expiresAt: token.expiresAt)
  }
}

struct DocumentAIOAuthTransport: GatewayHTTPTransport {
  let transport: any DocumentAIHTTPTransport
  func send(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
    var converted = URLRequest(url: request.url); converted.httpMethod = request.method
    converted.httpBody = request.body
    for (name, value) in request.headers { converted.setValue(value, forHTTPHeaderField: name) }
    let response = try await transport.send(converted)
    return GatewayHTTPResponse(statusCode: response.status, body: response.body)
  }
}

actor DocumentAIStoredOAuthTokenProvider: DocumentAIAccessTokenProvider {
  let auth: DocumentAIInteractiveAuth
  let environment: [String: String]
  let id: String
  init(auth: DocumentAIInteractiveAuth, environment: [String: String], id: String = "google-personal") {
    self.auth = auth; self.environment = environment; self.id = id
  }
  func accessToken() async throws -> String {
    let selected = auth.credentialEnvironment(id: id, environment: environment)
    let url = auth.tokenURL(id: id, environment: selected)
    let token = try DocumentAIOAuthStorage.read(url)
    guard Set(token.scopes) == [DocumentAIInteractiveAuth.scope] else { throw DocumentAIError.missingCredential("Stored OAuth scope is invalid") }
    if token.expiresAt > Date().addingTimeInterval(60) { return try await DocumentAIStaticTokenProvider(token: token.accessToken).accessToken() }
    let client = try auth.applicationClient(environment: selected)
    let refreshed: OAuthTokenCredential
    do { refreshed = try await auth.oauth.refresh(credential: auth.sharedToken(token), client: client) } catch { throw DocumentAIError.missingCredential("Stored OAuth refresh failed") }
    guard Set(refreshed.scopes) == [DocumentAIInteractiveAuth.scope] else { throw DocumentAIError.missingCredential("Refreshed OAuth scope is invalid") }
    let store = DocumentAIOAuthTokenStore(accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken,
                                        tokenType: refreshed.tokenType, scopes: refreshed.scopes, expiresAt: refreshed.expiresAt)
    try DocumentAIOAuthStorage.write(store, to: url)
    return try await DocumentAIStaticTokenProvider(token: store.accessToken).accessToken()
  }
}
