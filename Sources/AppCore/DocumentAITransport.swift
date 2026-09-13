import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DocumentAIHTTPResponse: Sendable {
  public let status: Int
  public let body: Data

  public init(status: Int, body: Data) {
    self.status = status
    self.body = body
  }
}

public protocol DocumentAIHTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> DocumentAIHTTPResponse
}

public struct DocumentAIURLSessionTransport: DocumentAIHTTPTransport {
  private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
      completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }
  }

  public init() {}

  public func send(_ request: URLRequest) async throws -> DocumentAIHTTPResponse {
    let session = URLSession(configuration: .ephemeral, delegate: RedirectDelegate(), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    let (body, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw DocumentAIError.transport }
    return DocumentAIHTTPResponse(status: response.statusCode, body: body)
  }
}

public protocol DocumentAIAccessTokenProvider: Sendable {
  func accessToken() async throws -> String
}

public struct DocumentAIEnvironmentTokenProvider: DocumentAIAccessTokenProvider {
  public let variable: String

  public init(variable: String = "GOOGLE_DOCUMENT_OCR_ACCESS_TOKEN") { self.variable = variable }

  public func accessToken() async throws -> String {
    guard let token = ProcessInfo.processInfo.environment[variable], !token.isEmpty else {
      throw DocumentAIError.missingCredential(variable)
    }
    return token
  }
}
