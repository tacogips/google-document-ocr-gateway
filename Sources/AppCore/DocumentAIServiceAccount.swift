import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public protocol DocumentAIJWTSigner: Sendable {
  func sign(message: Data, privateKeyPEM: String) throws -> Data
}

/// Uses the macOS OpenSSL executable; temporary private-key material is owner-only and removed on return.
public struct DocumentAIOpenSSLSigner: DocumentAIJWTSigner {
  public init() {}

  public func sign(message: Data, privateKeyPEM: String) throws -> Data {
    var template = Array("/tmp/document-ai-signing.XXXXXX".utf8CString)
    let descriptor = template.withUnsafeMutableBufferPointer { buffer -> Int32 in
      guard let base = buffer.baseAddress else { return -1 }
      return mkstemp(base)
    }
    guard descriptor >= 0 else { throw DocumentAIError.missingCredential("Cannot create signing file") }
    let path = String(bytes: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
    defer { close(descriptor); unlink(path) }
    guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
      throw DocumentAIError.missingCredential("Cannot secure signing file")
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    do { try handle.write(contentsOf: Data(privateKeyPEM.utf8)) } catch {
      throw DocumentAIError.missingCredential("Cannot prepare signing key")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
    process.arguments = ["dgst", "-sha256", "-sign", path]
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      try input.fileHandleForWriting.write(contentsOf: message)
      try input.fileHandleForWriting.close()
      let signature = try output.fileHandleForReading.readToEnd() ?? Data()
      process.waitUntilExit()
      guard process.terminationStatus == 0, !signature.isEmpty else {
        throw DocumentAIError.missingCredential("RSA signing failed")
      }
      return signature
    } catch {
      if process.isRunning { process.terminate(); process.waitUntilExit() }
      throw DocumentAIError.missingCredential("RSA signing failed")
    }
  }
}

/// Exchanges service-account assertions for OAuth tokens and refreshes them before expiry.
public actor DocumentAIServiceAccountTokenProvider: DocumentAIAccessTokenProvider {
  private struct Credential: Decodable, Sendable {
    let type: String
    let clientEmail: String
    let privateKey: String
    let tokenUri: String
  }

  private let credential: Credential
  private let transport: any DocumentAIHTTPTransport
  private let signer: any DocumentAIJWTSigner
  private let now: @Sendable () -> Date
  private var cached: (token: String, expiry: Date)?

  public init(
    credentialJSON: Data,
    transport: any DocumentAIHTTPTransport = DocumentAIURLSessionTransport(),
    signer: any DocumentAIJWTSigner = DocumentAIOpenSSLSigner(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let credential = try? decoder.decode(Credential.self, from: credentialJSON),
          credential.type == "service_account", credential.clientEmail.contains("@"),
          credential.clientEmail.count < 320,
          credential.privateKey.hasPrefix("-----BEGIN PRIVATE KEY-----"),
          credential.tokenUri == "https://oauth2.googleapis.com/token" else {
      throw DocumentAIError.missingCredential("Invalid service-account JSON")
    }
    self.credential = credential
    self.transport = transport
    self.signer = signer
    self.now = now
  }

  public func accessToken() async throws -> String {
    let instant = now()
    if let cached, cached.expiry > instant.addingTimeInterval(60) { return cached.token }
    guard let url = URL(string: credential.tokenUri) else { throw DocumentAIError.missingCredential("Invalid token endpoint") }
    let header = Self.base64URL(Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8))
    let claims = try JSONSerialization.data(withJSONObject: [
      "iss": credential.clientEmail, "aud": credential.tokenUri,
      "scope": "https://www.googleapis.com/auth/cloud-platform",
      "iat": Int(instant.timeIntervalSince1970), "exp": Int(instant.timeIntervalSince1970) + 3600
    ])
    let unsigned = "\(header).\(Self.base64URL(claims))"
    let signature: Data
    do { signature = try signer.sign(message: Data(unsigned.utf8), privateKeyPEM: credential.privateKey) } catch {
      throw DocumentAIError.missingCredential("Service-account signing failed")
    }
    let assertion = "\(unsigned).\(Self.base64URL(signature))"
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(assertion)".utf8)
    let response: DocumentAIHTTPResponse
    do { response = try await transport.send(request) } catch is CancellationError {
      throw CancellationError()
    } catch { throw DocumentAIError.missingCredential("Token exchange failed") }
    struct Token: Decodable { let accessToken: String; let expiresIn: Double; let tokenType: String }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard (200..<300).contains(response.status),
          let result = try? decoder.decode(Token.self, from: response.body),
          result.tokenType == "Bearer", !result.accessToken.isEmpty,
          result.accessToken.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }),
          result.expiresIn.isFinite, result.expiresIn > 0 else {
      throw DocumentAIError.missingCredential("Token exchange returned an invalid response")
    }
    cached = (result.accessToken, instant.addingTimeInterval(result.expiresIn))
    return result.accessToken
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
}
