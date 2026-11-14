import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AppCore

private func credential(endpoint: String = "https://oauth2.googleapis.com/token") throws -> Data {
  try JSONSerialization.data(withJSONObject: [
    "type": "service_account", "client_email": "test@example.iam.gserviceaccount.com",
    "private_key": "-----BEGIN PRIVATE KEY-----\nfixture", "token_uri": endpoint
  ])
}

private struct AssertionSigner: DocumentAIJWTSigner {
  func sign(message: Data, privateKeyPEM: String) throws -> Data {
    let text = try #require(String(data: message, encoding: .utf8))
    let components = text.split(separator: ".")
    #expect(components.count == 2)
    var base64 = String(components[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while !base64.count.isMultiple(of: 4) { base64 += "=" }
    let data = try #require(Data(base64Encoded: base64))
    let claims = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(claims["aud"] as? String == "https://oauth2.googleapis.com/token")
    #expect(claims["scope"] as? String == "https://www.googleapis.com/auth/cloud-platform")
    #expect(claims["iat"] as? Int == 1000)
    #expect(claims["exp"] as? Int == 4600)
    return Data("signature".utf8)
  }
}

private actor TokenTransport: DocumentAIHTTPTransport {
  var calls = 0
  let failure: Bool
  init(failure: Bool = false) { self.failure = failure }

  func send(_ request: URLRequest) async throws -> DocumentAIHTTPResponse {
    calls += 1
    #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    let body = try #require(request.httpBody)
    #expect(String(data: body, encoding: .utf8)?.hasPrefix("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=") == true)
    return DocumentAIHTTPResponse(status: failure ? 400 : 200, body: Data(
      (failure ? #"{"error":"secret-credential"}"# : #"{"access_token":"token","token_type":"Bearer","expires_in":3600}"#).utf8
    ))
  }
}

@Test func serviceAccountExchangesAndCachesToken() async throws {
  let transport = TokenTransport()
  let provider = try DocumentAIServiceAccountTokenProvider(
    credentialJSON: credential(), transport: transport, signer: AssertionSigner(), now: { Date(timeIntervalSince1970: 1000) }
  )
  #expect(try await provider.accessToken() == "token")
  #expect(try await provider.accessToken() == "token")
  #expect(await transport.calls == 1)
}

@Test func rejectsUntrustedTokenEndpointAndHidesExchangeFailure() async throws {
  #expect(throws: DocumentAIError.self) {
    try DocumentAIServiceAccountTokenProvider(credentialJSON: credential(endpoint: "https://example.com/token"))
  }
  let provider = try DocumentAIServiceAccountTokenProvider(
    credentialJSON: credential(), transport: TokenTransport(failure: true), signer: AssertionSigner(), now: { Date(timeIntervalSince1970: 1000) }
  )
  do {
    _ = try await provider.accessToken()
    Issue.record("Expected token failure")
  } catch {
    let failure = DocumentAICLI.failure(error, command: "writer")
    #expect(failure.exitCode == 3)
    #expect(String(data: failure.data, encoding: .utf8)?.contains("secret-credential") == false)
  }
}

@Test func opensslSignerSignsGeneratedKey() throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
  process.arguments = ["genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048"]
  let output = Pipe()
  process.standardOutput = output
  process.standardError = FileHandle.nullDevice
  try process.run()
  let bytes = try #require(try output.fileHandleForReading.readToEnd())
  process.waitUntilExit()
  #expect(process.terminationStatus == 0)
  let key = try #require(String(data: bytes, encoding: .utf8))
  let signature = try DocumentAIOpenSSLSigner().sign(message: Data("test assertion".utf8), privateKeyPEM: key)
  #expect(signature.count == 256)
}
