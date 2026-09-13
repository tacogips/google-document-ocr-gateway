import Foundation
import AppCore

let arguments = Array(CommandLine.arguments.dropFirst())
do {
  let output = try await DocumentAICLI(arguments: arguments).run()
  FileHandle.standardOutput.write(output)
  FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
  let failure = DocumentAICLI.failure(error, command: arguments.first)
  FileHandle.standardError.write(failure.data)
  FileHandle.standardError.write(Data("\n".utf8))
  exit(failure.exitCode)
}
