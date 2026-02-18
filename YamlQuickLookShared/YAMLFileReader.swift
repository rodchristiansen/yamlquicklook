import Foundation

/// Shared file-reading and content-preparation logic for the YAML Quick Look extensions.
///
/// This type is compiled into both extensions and the test target. It is a
/// pure value type with no mutable state and is inherently thread-safe.
enum YAMLFileReader {

    /// The default maximum number of bytes read into memory at once.
    static let defaultMaxFileSize: UInt64 = 10 * 1024 * 1024 // 10 MB

    // MARK: - ReadResult

    enum ReadResult {
        /// The entire file was decoded successfully.
        case complete(String)
        /// The file exceeded `maxFileSize` and only the first portion was read.
        case truncated(String, fileSizeMB: UInt64)

        /// The decoded text, regardless of whether truncation occurred.
        var content: String {
            switch self {
            case .complete(let text): return text
            case .truncated(let text, _): return text
            }
        }
    }

    // MARK: - Read

    /// Reads the file at `url`, returning `.truncated` for files exceeding `maxFileSize`.
    ///
    /// Encoding resolution order:
    /// 1. UTF-8 (strict)
    /// 2. ISO Latin-1 (for legacy files with non-UTF-8 bytes)
    /// 3. Lossy UTF-8 via `String(decoding:as:)` — substitutes U+FFFD, never fails
    ///
    /// The `maxFileSize` parameter defaults to `defaultMaxFileSize` (10 MB).
    /// Tests may pass a smaller value to avoid creating large temp files.
    static func read(
        fileAt url: URL,
        maxFileSize: UInt64 = defaultMaxFileSize
    ) throws -> ReadResult {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? UInt64) ?? 0

        if fileSize > maxFileSize {
            // Read exactly maxFileSize bytes. String(decoding:as:) never throws and
            // substitutes U+FFFD for any UTF-8 sequences that were cut at the boundary.
            let handle = try FileHandle(forReadingFrom: url)
            defer { handle.closeFile() }
            let data = handle.readData(ofLength: Int(maxFileSize))
            return .truncated(
                String(decoding: data, as: UTF8.self),
                fileSizeMB: fileSize / 1024 / 1024
            )
        }

        return .complete(try readString(from: url))
    }

    // MARK: - Snippet

    /// Converts raw file content into a display snippet of at most `maxLines` lines.
    ///
    /// - Strips leading/trailing whitespace.
    /// - Normalises all line-ending styles (CRLF, bare CR) to LF before splitting.
    /// - Appends `"\n..."` when content exceeds `maxLines`.
    static func makeSnippet(from content: String, maxLines: Int = 60) -> String {
        let normalized = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return normalized }
        return lines.prefix(maxLines).joined(separator: "\n") + "\n..."
    }

    // MARK: - Private

    private static func readString(from url: URL) throws -> String {
        // 1. Try strict UTF-8 first (the common case)
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        // 2. Fall back to ISO Latin-1, which decodes every byte value without throwing.
        //    Useful for Ansible vaults or any YAML hand-edited on non-UTF-8 systems.
        if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            return latin1
        }
        // 3. Last resort: load raw bytes and substitute replacement chars for invalid UTF-8.
        //    This never throws and always returns something displayable.
        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
    }
}
