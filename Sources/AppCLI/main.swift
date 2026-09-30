import GoogleGatewayAuth
import Foundation
import AppCore

let gatewayInvocation = GatewayAuthBootstrap.prepareOrExit(product: .ocr, role: "writer")

let arguments = gatewayInvocation.arguments
do {
  let output = try await DocumentAICLI(arguments: arguments, environment: gatewayInvocation.environment).run()
  FileHandle.standardOutput.write(output)
  FileHandle.standardOutput.write(Data("\n".utf8))
  exit(gatewayInvocation.complete(exitCode: 0))
} catch {
  let failure = DocumentAICLI.failure(error, command: arguments.first)
  FileHandle.standardError.write(failure.data)
  FileHandle.standardError.write(Data("\n".utf8))
  exit(failure.exitCode)
}
