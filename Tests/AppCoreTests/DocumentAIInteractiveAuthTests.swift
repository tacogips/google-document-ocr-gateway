import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GoogleServiceGatewayCore
import Testing
@testable import AppCore

private let desktopJSON = #"{"installed":{"client_id":"ocr-desktop","auth_uri":"https://accounts.google.com/o/oauth2/v2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://127.0.0.1"]}}"#

@Test func ocrBrowserLoginPersistsPrivateRefreshableTokenThenExecutesWithoutLogin() async throws {
  let root = try authRoot(); defer { try? FileManager.default.removeItem(at: root) }
  let env = ["XDG_STATE_HOME": root.path, "GOOGLE_DOCUMENT_OCR_GATEWAY_OAUTH_CLIENT_JSON": desktopJSON]
  let transport = OCRAuthTransport()
  let cli = DocumentAICLI(arguments: ["auth", "login"], transport: transport, environment: env, authAuthorizer: OCRFixtureAuthorizer())
  let output = try await cli.run()
  #expect(String(data: output, encoding: .utf8)?.contains("READY") == true)
  #expect(String(data: output, encoding: .utf8)?.contains("login-token") == false)
  let auth = DocumentAIInteractiveAuth(transport: transport)
  let url = auth.tokenURL(environment: env)
  let stored = try DocumentAIOAuthStorage.read(url)
  #expect(stored.refreshToken == "refresh-token")
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  let result = try await DocumentAICLI(arguments: ["reader", "projects.locations.processors.get", "--param", "name=projects/123/locations/us/processors/processor"],
                                     transport: transport, environment: ["XDG_STATE_HOME": root.path]).run()
  #expect(String(data: result, encoding: .utf8)?.contains("processor") == true)
  let status = try await DocumentAICLI(arguments: ["auth", "status"], environment: ["XDG_STATE_HOME": root.path]).run()
  #expect(String(data: status, encoding: .utf8)?.contains("READY") == true)
  _ = try await DocumentAICLI(arguments: ["auth", "revoke", "--credential", "google-personal", "--confirm-credential", "google-personal"],
                              transport: transport, environment: env).run()
  #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func ocrMissingClientAndBadTimeoutDoNotEnterBrowserAuthorization() async throws {
  let auth = DocumentAIInteractiveAuth(authorizer: OCRNeverAuthorizer())
  await #expect(throws: DocumentAIError.self) { try await auth.run(arguments: ["login"], environment: [:]) }
  await #expect(throws: DocumentAIError.self) {
    try await auth.run(arguments: ["login", "--timeout-seconds", "invalid"], environment: ["GOOGLE_DOCUMENT_OCR_GATEWAY_OAUTH_CLIENT_JSON": desktopJSON])
  }
  await #expect(throws: DocumentAIError.self) {
    try await auth.run(arguments: ["revoke", "--credential", "google-personal"], environment: [:])
  }
}

@Test func ocrIncompleteLoginGrantLeavesExistingTokenUntouched() async throws {
  let root = try authRoot(); defer { try? FileManager.default.removeItem(at: root) }
  let env = ["XDG_STATE_HOME": root.path, "GOOGLE_DOCUMENT_OCR_GATEWAY_OAUTH_CLIENT_JSON": desktopJSON]
  let auth = DocumentAIInteractiveAuth(transport: OCRAuthTransport(missingRefresh: true), authorizer: OCRFixtureAuthorizer())
  let path = auth.tokenURL(environment: env)
  try DocumentAIOAuthStorage.write(.init(accessToken: "old-token", scopes: [DocumentAIInteractiveAuth.scope], expiresAt: .distantFuture), to: path)
  let before = try Data(contentsOf: path)
  await #expect(throws: DocumentAIError.self) { try await auth.run(arguments: ["login"], environment: env) }
  #expect(try Data(contentsOf: path) == before)
}

@Test func ocrBroaderLoginGrantNeverPersistsAndStatusRejectsIt() async throws {
  let root = try authRoot(); defer { try? FileManager.default.removeItem(at: root) }
  let env = ["XDG_STATE_HOME": root.path, "GOOGLE_DOCUMENT_OCR_GATEWAY_OAUTH_CLIENT_JSON": desktopJSON]
  let auth = DocumentAIInteractiveAuth(transport: OCRAuthTransport(extraScope: true), authorizer: OCRFixtureAuthorizer())
  let path = auth.tokenURL(environment: env)
  await #expect(throws: DocumentAIError.self) { try await auth.run(arguments: ["login"], environment: env) }
  #expect(!FileManager.default.fileExists(atPath: path.path))
  try DocumentAIOAuthStorage.write(.init(accessToken: "fixture-token", scopes: [DocumentAIInteractiveAuth.scope, "https://www.googleapis.com/auth/drive.readonly"], expiresAt: .distantFuture), to: path)
  let status = try await auth.run(arguments: ["status"], environment: env)
  #expect(String(data: status, encoding: .utf8)?.contains("INVALID") == true)
}

@Test func ocrStoredTokenRefreshesAndPersistsRotatedGrant() async throws {
  let root = try authRoot(); defer { try? FileManager.default.removeItem(at: root) }
  let env = ["XDG_STATE_HOME": root.path, "GOOGLE_DOCUMENT_OCR_GATEWAY_OAUTH_CLIENT_JSON": desktopJSON]
  let auth = DocumentAIInteractiveAuth(transport: OCRAuthTransport())
  let path = auth.tokenURL(environment: env)
  try DocumentAIOAuthStorage.write(.init(accessToken: "old-token", refreshToken: "refresh-token", scopes: [DocumentAIInteractiveAuth.scope], expiresAt: .distantPast), to: path)
  let provider = DocumentAIStoredOAuthTokenProvider(auth: auth, environment: env)
  #expect(try await provider.accessToken() == "login-token")
  #expect(try DocumentAIOAuthStorage.read(path).expiresAt > Date())
}

@Test func ocrExternalCredentialsRemainIndependentOfInteractiveAuth() async throws {
  let provider = try #require(try DocumentAIExternalCredentials.tokenProvider(environment: ["GOOGLE_DOCUMENT_OCR_GATEWAY_ACCESS_TOKEN": "external-token"]))
  #expect(try await provider.accessToken() == "external-token")
  let token = DocumentAIOAuthTokenStore(accessToken: "json-token", expiresAt: .distantFuture)
  let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
  let json = try #require(String(data: encoder.encode(token), encoding: .utf8))
  let inline = try #require(try DocumentAIExternalCredentials.tokenProvider(environment: ["GOOGLE_DOCUMENT_OCR_GATEWAY_TOKEN_STORE_JSON": json]))
  #expect(try await inline.accessToken() == "json-token")
  #expect(throws: DocumentAIError.self) {
    _ = try DocumentAIExternalCredentials.tokenProvider(environment: ["GOOGLE_DOCUMENT_OCR_GATEWAY_ACCESS_TOKEN": "token", "GOOGLE_DOCUMENT_OCR_GATEWAY_TOKEN_STORE_JSON": json])
  }
  #expect(throws: DocumentAIError.self) {
    _ = try DocumentAIExternalCredentials.tokenProvider(environment: ["GOOGLE_DOCUMENT_OCR_GATEWAY_ACCESS_TOKEN": "bad\ntoken"])
  }
}

@Test func ocrStatusDoesNotFallBackFromInvalidInlineJSONToSavedToken() async throws {
  let root = try authRoot(); defer { try? FileManager.default.removeItem(at: root) }
  let auth = DocumentAIInteractiveAuth()
  var env = ["XDG_STATE_HOME": root.path]
  try DocumentAIOAuthStorage.write(.init(accessToken: "saved-token", scopes: [DocumentAIInteractiveAuth.scope], expiresAt: .distantFuture),
                                  to: auth.tokenURL(environment: env))
  env["GOOGLE_DOCUMENT_OCR_GATEWAY_TOKEN_STORE_JSON"] = "invalid-json"
  let status = try await auth.run(arguments: ["status"], environment: env)
  #expect(String(data: status, encoding: .utf8)?.contains("INVALID") == true)
  #expect(String(data: status, encoding: .utf8)?.contains("saved-token") == false)
}

@Test func ocrProfileTokenSourceOverridesProductDefaultPath() async throws {
  let env = ["GOOGLE_DOCUMENT_OCR_GATEWAY_TOKEN_STORE_PATH": "/unused/global.json",
             "GOOGLE_DOCUMENT_OCR_GATEWAY_CREDENTIAL_WORK_ACCESS_TOKEN": "external-token"]
  let provider = try #require(try DocumentAIExternalCredentials.tokenProvider(environment: env, credentialID: "work"))
  #expect(try await provider.accessToken() == "external-token")
  let auth = DocumentAIInteractiveAuth()
  let selected = auth.credentialEnvironment(id: "work", environment: env)
  #expect(selected["GOOGLE_DOCUMENT_OCR_GATEWAY_TOKEN_STORE_PATH"] == nil)
  #expect(selected["GOOGLE_DOCUMENT_OCR_GATEWAY_ACCESS_TOKEN"] == "external-token")
}

private func authRoot() throws -> URL {
  let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  return root
}

private struct OCRFixtureAuthorizer: InteractiveOAuthAuthorizer {
  func authorize(client: OAuthClientConfiguration, scopes: [String], loginHint: String?, openBrowser: Bool,
                 timeout: TimeInterval) async throws -> (code: String, request: OAuthAuthorizationRequest) {
    #expect(scopes == [DocumentAIInteractiveAuth.scope])
    let request = try GoogleOAuthClient().authorizationRequest(client: client, redirectURI: try #require(URL(string: "http://127.0.0.1:12345/callback")), scopes: scopes)
    return ("authorization-code", request)
  }
}

private struct OCRNeverAuthorizer: InteractiveOAuthAuthorizer {
  func authorize(client: OAuthClientConfiguration, scopes: [String], loginHint: String?, openBrowser: Bool,
                 timeout: TimeInterval) async throws -> (code: String, request: OAuthAuthorizationRequest) {
    Issue.record("Authorization must not run")
    throw DocumentAIError.transport
  }
}

private struct OCRAuthTransport: DocumentAIHTTPTransport {
  var missingRefresh = false
  var extraScope = false
  func send(_ request: URLRequest) async throws -> DocumentAIHTTPResponse {
    if request.url?.host == "oauth2.googleapis.com" {
      if request.url?.path == "/revoke" { return DocumentAIHTTPResponse(status: 200, body: Data()) }
      let refresh = missingRefresh ? "" : #", "refresh_token":"refresh-token""#
      let body = #"{"access_token":"login-token","token_type":"Bearer","expires_in":3600,"scope":"https://www.googleapis.com/auth/cloud-platform""# + refresh + "}"
      let result = extraScope ? body.replacingOccurrences(of: "https://www.googleapis.com/auth/cloud-platform", with: "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/drive.readonly") : body
      return DocumentAIHTTPResponse(status: 200, body: Data(result.utf8))
    }
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer login-token")
    return DocumentAIHTTPResponse(status: 200, body: Data(#"{"name":"processor"}"#.utf8))
  }
}
