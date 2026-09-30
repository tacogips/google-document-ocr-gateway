import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Private, atomic persistence for browser-acquired credentials.
enum DocumentAIOAuthStorage {
  static func read(_ url: URL) throws -> DocumentAIOAuthTokenStore {
    let data = try DocumentAIExternalCredentials.data(url.path, isPath: true)
    return try DocumentAIExternalCredentials.decodeTokenStore(data)
  }

  static func write(_ token: DocumentAIOAuthTokenStore, to url: URL) throws {
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let directory = parent.path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
    guard directory >= 0 else { throw DocumentAIError.missingCredential("Credential directory is unavailable") }
    defer { close(directory) }
    var metadata = stat()
    guard fstat(directory, &metadata) == 0, metadata.st_uid == getuid(), metadata.st_mode & 0o077 == 0 else {
      throw DocumentAIError.missingCredential("Credential directory must be private and owned by the current user")
    }
    let leaf = url.lastPathComponent
    var existing = stat()
    if fstatat(directory, leaf, &existing, AT_SYMLINK_NOFOLLOW) == 0 {
      guard existing.st_mode & S_IFMT == S_IFREG, existing.st_uid == getuid(), existing.st_mode & 0o077 == 0 else {
        throw DocumentAIError.missingCredential("Existing credential file is unsafe")
      }
    } else if errno != ENOENT { throw DocumentAIError.missingCredential("Credential destination is unavailable") }
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(token)
    let temporary = ".oauth-" + UUID().uuidString
    let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw DocumentAIError.missingCredential("Unable to create credential file") }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { unlinkat(directory, temporary, 0) }
    try handle.write(contentsOf: data)
    guard fsync(descriptor) == 0, renameat(directory, temporary, directory, leaf) == 0 else {
      throw DocumentAIError.missingCredential("Unable to persist credential file")
    }
  }

  static func remove(_ url: URL) throws {
    _ = try read(url)
    try FileManager.default.removeItem(at: url)
  }
}
