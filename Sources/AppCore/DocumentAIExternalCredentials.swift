import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct DocumentAIOAuthTokenStore: Codable, Sendable {
  public let accessToken: String
  public let refreshToken: String?
  public let tokenType: String
  public let scopes: [String]
  public let expiresAt: Date

  public init(accessToken: String, refreshToken: String? = nil, tokenType: String = "Bearer",
              scopes: [String] = [], expiresAt: Date) {
    self.accessToken = accessToken; self.refreshToken = refreshToken; self.tokenType = tokenType
    self.scopes = scopes; self.expiresAt = expiresAt
  }
}

public enum DocumentAIExternalCredentials {
  public static func tokenProvider(
    environment: [String: String], credentialID: String? = nil,
    tokenVariable: String = "GOOGLE_DOCUMENT_OCR_GATEWAY_ACCESS_TOKEN",
    transport: any DocumentAIHTTPTransport = DocumentAIURLSessionTransport()
  ) throws -> (any DocumentAIAccessTokenProvider)? {
    let base = "GOOGLE_DOCUMENT_OCR_GATEWAY_"
    let specific = credentialID.map { base + "CREDENTIAL_" + $0.uppercased().replacingOccurrences(of: "-", with: "_") + "_" }
    let suffixes = ["ACCESS_TOKEN", "TOKEN_STORE_JSON", "TOKEN_STORE_PATH", "SERVICE_ACCOUNT_JSON", "SERVICE_ACCOUNT_PATH"]
    let useSpecific = specific.map { prefix in suffixes.contains { nonBlank(environment[prefix + $0]) != nil } } ?? false
    let prefix = useSpecific ? specific ?? base : base
    let selected = suffixes.compactMap { suffix in nonBlank(environment[prefix + suffix]).map { (suffix, $0) } }
    let alias = useSpecific ? nil : nonBlank(environment[tokenVariable])
    if let canonical = selected.first(where: { $0.0 == "ACCESS_TOKEN" }), let alias, canonical.1 != alias {
      throw DocumentAIError.invalidArgument("Conflicting token environment variables")
    }
    guard selected.count <= 1, !(alias != nil && selected.contains(where: { $0.0 != "ACCESS_TOKEN" })) else {
      throw DocumentAIError.invalidArgument("Choose one external credential source")
    }
    guard let entry = selected.first else {
      if let alias { return try DocumentAIStaticTokenProvider(token: alias) }
      return nil
    }
    switch entry.0 {
    case "ACCESS_TOKEN": return try DocumentAIStaticTokenProvider(token: entry.1)
    case "TOKEN_STORE_JSON", "TOKEN_STORE_PATH":
      let data = try data(entry.1, isPath: entry.0 == "TOKEN_STORE_PATH")
      let store = try decodeTokenStore(data)
      guard store.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame, store.expiresAt > Date().addingTimeInterval(60) else {
        throw DocumentAIError.missingCredential("Expired or invalid external token; supply replacement credentials")
      }
      return try DocumentAIStaticTokenProvider(token: store.accessToken)
    default:
      return try DocumentAIServiceAccountTokenProvider(
        credentialJSON: data(entry.1, isPath: entry.0 == "SERVICE_ACCOUNT_PATH"), transport: transport)
    }
  }

  static func decodeTokenStore(_ data: Data) throws -> DocumentAIOAuthTokenStore {
    do {
      let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
      if let token = try? decoder.decode(DocumentAIOAuthTokenStore.self, from: data) { return token }
      return try JSONDecoder().decode(DocumentAIOAuthTokenStore.self, from: data)
    } catch { throw DocumentAIError.missingCredential("Invalid token-store JSON") }
  }

  static func data(_ value: String, isPath: Bool) throws -> Data {
    let limit = 1_048_576
    if !isPath {
      guard value.utf8.count <= limit else { throw DocumentAIError.invalidArgument("Credential JSON is too large") }
      return Data(value.utf8)
    }
    let descriptor = value.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) }
    guard descriptor >= 0 else { throw DocumentAIError.missingCredential("Credential file is unavailable") }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
          metadata.st_uid == getuid(), metadata.st_mode & 0o077 == 0 else {
      throw DocumentAIError.missingCredential("Credential file must be a private regular file owned by the current user")
    }
    let result: Data
    do { result = try handle.read(upToCount: limit + 1) ?? Data() } catch { throw DocumentAIError.missingCredential("Credential file could not be read") }
    guard result.count <= limit else { throw DocumentAIError.invalidArgument("Credential file is too large") }
    return result
  }

  private static func nonBlank(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

public struct DocumentAIStaticTokenProvider: DocumentAIAccessTokenProvider {
  private let token: String
  public init(token: String) throws {
    guard !token.isEmpty, token.utf8.count <= 8192, !token.utf8.contains(where: { $0 < 33 || $0 == 127 }) else {
      throw DocumentAIError.missingCredential("Access token contains unsupported characters")
    }
    self.token = token
  }
  public func accessToken() async throws -> String { token }
}
