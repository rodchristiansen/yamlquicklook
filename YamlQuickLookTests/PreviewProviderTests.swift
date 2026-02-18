import XCTest
import Foundation

/// Battle tests for YAMLFileReader — the shared file-reading and content preparation logic.
///
/// Covers: encoding fallbacks, file-size truncation, UTF-8 boundary safety,
/// snippet line-count boundaries, line-ending normalisation, and real-world YAML formats.
final class YAMLFileReaderTests: XCTestCase {

    // MARK: - Helpers

    private func writeTempFile(name: String, content: String) throws -> URL {
        try writeTempFile(name: name, data: Data(content.utf8))
    }

    private func writeTempFile(name: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ql-test-\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // -------------------------------------------------------------------------
    // MARK: - Read: Basic
    // -------------------------------------------------------------------------

    func testRead_emptyFile_returnsCompleteEmptyString() throws {
        let url = try writeTempFile(name: "empty.yaml", data: Data())
        let result = try YAMLFileReader.read(fileAt: url)
        guard case .complete(let text) = result else { return XCTFail("Expected .complete") }
        XCTAssertEqual(text, "")
    }

    func testRead_singleLine_returnsText() throws {
        let url = try writeTempFile(name: "single.yaml", content: "key: value")
        let result = try YAMLFileReader.read(fileAt: url)
        guard case .complete(let text) = result else { return XCTFail("Expected .complete") }
        XCTAssertEqual(text, "key: value")
    }

    func testRead_multiline_returnsFullContent() throws {
        let content = "host: server01\nport: 8080\nenabled: true"
        let url = try writeTempFile(name: "multi.yaml", content: content)
        let result = try YAMLFileReader.read(fileAt: url)
        XCTAssertEqual(result.content, content)
    }

    // -------------------------------------------------------------------------
    // MARK: - Read: Encoding Fallbacks
    // -------------------------------------------------------------------------

    func testRead_utf8MultibyteCJK_preserved() throws {
        let content = "# 日本語コメント\nname: テスト\npath: /opt/アプリ"
        let url = try writeTempFile(name: "cjk.yaml", content: content)
        let result = try YAMLFileReader.read(fileAt: url)
        XCTAssertTrue(result.content.contains("日本語"))
        XCTAssertTrue(result.content.contains("テスト"))
    }

    func testRead_utf8Emoji_preserved() throws {
        let content = "status: ✅\nwarning: ⚠️\nerror: ❌"
        let url = try writeTempFile(name: "emoji.yaml", content: content)
        let result = try YAMLFileReader.read(fileAt: url)
        XCTAssertTrue(result.content.contains("✅"))
        XCTAssertTrue(result.content.contains("❌"))
    }

    func testRead_invalidUTF8_fallsBackWithoutThrowing() throws {
        // 0xFF and 0x80 are never valid UTF-8 bytes — triggers the Latin-1 / lossy fallback
        let invalidUTF8: [UInt8] = Array("author: caf".utf8) + [0xFF, 0x80] + Array("\n".utf8)
        let url = try writeTempFile(name: "latin1.yaml", data: Data(invalidUTF8))
        XCTAssertNoThrow(try YAMLFileReader.read(fileAt: url))
        let result = try YAMLFileReader.read(fileAt: url)
        XCTAssertFalse(result.content.isEmpty, "Content must not be empty on encoding fallback")
    }

    func testRead_allByteValues_doesNotThrow() throws {
        // Stress test: every possible byte value in a 256-byte file
        let allBytes = Data((0...255).map { UInt8($0) })
        let url = try writeTempFile(name: "allbytes.yaml", data: allBytes)
        XCTAssertNoThrow(try YAMLFileReader.read(fileAt: url))
    }

    func testRead_randomBinaryFile_doesNotThrow() throws {
        // Simulate a .yaml extension on a binary file (e.g. macOS plist accidentally renamed)
        var bytes = [UInt8](repeating: 0, count: 512)
        for i in 0..<bytes.count { bytes[i] = UInt8((i * 137) % 256) }
        let url = try writeTempFile(name: "binary.yaml", data: Data(bytes))
        XCTAssertNoThrow(try YAMLFileReader.read(fileAt: url))
    }

    func testRead_nonExistentFile_throws() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).yaml")
        XCTAssertThrowsError(try YAMLFileReader.read(fileAt: url)) { error in
            // Must be a file-system error, not a crash or silent failure
            XCTAssertNotNil((error as NSError).domain)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Read: File-Size Guard (uses small custom maxFileSize for speed)
    // -------------------------------------------------------------------------

    private let smallLimit: UInt64 = 512 // 512 bytes — fast boundary testing

    func testRead_fileExactlyAtLimit_isComplete() throws {
        let data = Data(repeating: UInt8(ascii: "a"), count: Int(smallLimit))
        let url = try writeTempFile(name: "at-limit.yaml", data: data)
        let result = try YAMLFileReader.read(fileAt: url, maxFileSize: smallLimit)
        guard case .complete = result else {
            return XCTFail("File at exact limit should be .complete, not .truncated")
        }
    }

    func testRead_fileOneByteOverLimit_isTruncated() throws {
        let data = Data(repeating: UInt8(ascii: "b"), count: Int(smallLimit) + 1)
        let url = try writeTempFile(name: "over-limit.yaml", data: data)
        let result = try YAMLFileReader.read(fileAt: url, maxFileSize: smallLimit)
        guard case .truncated = result else {
            return XCTFail("File one byte over limit should be .truncated")
        }
    }

    func testRead_truncated_contentLengthEqualsLimit() throws {
        let size = Int(smallLimit) + 100
        let data = Data(repeating: UInt8(ascii: "x"), count: size)
        let url = try writeTempFile(name: "truncated-ascii.yaml", data: data)
        let result = try YAMLFileReader.read(fileAt: url, maxFileSize: smallLimit)
        guard case .truncated(let text, _) = result else { return XCTFail("Expected .truncated") }
        XCTAssertEqual(text.utf8.count, Int(smallLimit),
                       "Truncated content must be exactly maxFileSize bytes")
    }

    func testRead_truncated_fileSizeMBReportedCorrectly() throws {
        // Use real MB sizes for this one to validate the MB rounding arithmetic
        let fileMB: UInt64 = 2
        let limitMB: UInt64 = 1
        let data = Data(repeating: UInt8(ascii: "z"), count: Int(fileMB * 1024 * 1024))
        let url = try writeTempFile(name: "2mb.yaml", data: data)
        let result = try YAMLFileReader.read(fileAt: url, maxFileSize: limitMB * 1024 * 1024)
        guard case .truncated(_, let sizeMB) = result else { return XCTFail("Expected .truncated") }
        XCTAssertEqual(sizeMB, fileMB, "fileSizeMB should equal the actual file size in MB")
    }

    func testRead_truncatedWithMultibyteUnicodeAtBoundary_doesNotReturnEmpty() throws {
        // Construct content where a 3-byte UTF-8 character (あ) straddles the cut point.
        // String(decoding:as:) must return a non-empty string, substituting U+FFFD if needed.
        let japaneseChar = "あ" // 3 bytes in UTF-8 (0xE3 0x81 0x82)
        let line = String(repeating: japaneseChar, count: 50) + "\n"
        let lineCount = Int(smallLimit / UInt64(line.utf8.count)) + 5
        let content = String(repeating: line, count: lineCount)
        let url = try writeTempFile(name: "unicode-boundary.yaml", content: content)
        let result = try YAMLFileReader.read(fileAt: url, maxFileSize: smallLimit)
        guard case .truncated(let text, _) = result else { return XCTFail("Expected .truncated") }
        XCTAssertFalse(text.isEmpty,
                       "Truncated content must never be empty even when cut mid-character")
    }

    func testRead_contentHelper_returnsTextForBothCases() throws {
        // .complete
        let urlA = try writeTempFile(name: "helper-complete.yaml", content: "a: b")
        XCTAssertEqual(try YAMLFileReader.read(fileAt: urlA).content, "a: b")

        // .truncated
        let data = Data(repeating: UInt8(ascii: "c"), count: Int(smallLimit) + 1)
        let urlB = try writeTempFile(name: "helper-truncated.yaml", data: data)
        let truncText = try YAMLFileReader.read(fileAt: urlB, maxFileSize: smallLimit).content
        XCTAssertFalse(truncText.isEmpty)
    }

    // -------------------------------------------------------------------------
    // MARK: - makeSnippet: Line-Count Boundaries
    // -------------------------------------------------------------------------

    func testSnippet_emptyString() {
        XCTAssertEqual(YAMLFileReader.makeSnippet(from: ""), "")
    }

    func testSnippet_singleLine() {
        XCTAssertEqual(YAMLFileReader.makeSnippet(from: "key: value"), "key: value")
    }

    func testSnippet_59Lines_notTruncated() {
        let content = (1...59).map { "line\($0): val" }.joined(separator: "\n")
        let snippet = YAMLFileReader.makeSnippet(from: content)
        XCTAssertFalse(snippet.hasSuffix("..."))
        XCTAssertEqual(snippet.split(separator: "\n").count, 59)
    }

    func testSnippet_60Lines_notTruncated() {
        // Exactly at the limit — must NOT add "..."
        let content = (1...60).map { "line\($0): val" }.joined(separator: "\n")
        let snippet = YAMLFileReader.makeSnippet(from: content)
        XCTAssertFalse(snippet.hasSuffix("..."), "Exactly 60 lines must not be truncated")
        XCTAssertEqual(snippet.split(separator: "\n").count, 60)
    }

    func testSnippet_61Lines_appendsEllipsis() {
        // One line over — must truncate
        let content = (1...61).map { "line\($0): val" }.joined(separator: "\n")
        let snippet = YAMLFileReader.makeSnippet(from: content)
        XCTAssertTrue(snippet.hasSuffix("..."), "61 lines must produce trailing \"...\"")
        let lines = snippet.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 61, "Should be 60 content lines + \"...\" = 61 components")
    }

    func testSnippet_100Lines_preservesFirst60_dropsRest() {
        let content = (1...100).map { "line\($0): val" }.joined(separator: "\n")
        let snippet = YAMLFileReader.makeSnippet(from: content)
        XCTAssertTrue(snippet.hasPrefix("line1: val"))
        XCTAssertTrue(snippet.contains("line60: val"))
        XCTAssertFalse(snippet.contains("line61: val"), "line61 must be dropped")
        XCTAssertTrue(snippet.hasSuffix("..."))
    }

    func testSnippet_customMaxLines_respected() {
        let content = (1...10).map { "l\($0): v" }.joined(separator: "\n")
        let snippet = YAMLFileReader.makeSnippet(from: content, maxLines: 5)
        XCTAssertTrue(snippet.hasSuffix("..."))
        let lines = snippet.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 6, "5 content lines + \"...\" = 6")
    }

    // -------------------------------------------------------------------------
    // MARK: - makeSnippet: Line-Ending Normalisation
    // -------------------------------------------------------------------------

    func testSnippet_crlf_normalizedToLF() {
        let content = "key: value\r\nother: data\r\nthird: item"
        let snippet = YAMLFileReader.makeSnippet(from: content)
        XCTAssertFalse(snippet.contains("\r"), "CRLF must be normalized to LF")
        XCTAssertEqual(snippet.split(separator: "\n").count, 3)
    }

    func testSnippet_bareCR_normalizedToLF() {
        // Classic Mac (pre-OS X) uses bare CR
        let content = "key: value\rother: data\rthird: item"
        let snippet = YAMLFileReader.makeSnippet(from: content)
        XCTAssertFalse(snippet.contains("\r"), "Bare CR must be normalized to LF")
        XCTAssertEqual(snippet.split(separator: "\n").count, 3)
    }

    func testSnippet_mixedLineEndings_allNormalized() {
        let content = "a: 1\r\nb: 2\rc: 3\nd: 4"
        let snippet = YAMLFileReader.makeSnippet(from: content)
        XCTAssertFalse(snippet.contains("\r"))
        XCTAssertEqual(snippet.split(separator: "\n").count, 4)
    }

    func testSnippet_crlfAtTruncationBoundary_truncatesCorrectly() {
        // 65 lines with CRLF — should still cut at line 60
        let content = (1...65).map { "line\($0): val" }.joined(separator: "\r\n")
        let snippet = YAMLFileReader.makeSnippet(from: content)
        XCTAssertFalse(snippet.contains("\r"))
        XCTAssertTrue(snippet.hasSuffix("..."))
        XCTAssertTrue(snippet.contains("line60: val"))
        XCTAssertFalse(snippet.contains("line61: val"))
    }

    // -------------------------------------------------------------------------
    // MARK: - makeSnippet: Whitespace Handling
    // -------------------------------------------------------------------------

    func testSnippet_leadingTrailingWhitespace_stripped() {
        let content = "\n\n  key: value  \n\n"
        XCTAssertEqual(YAMLFileReader.makeSnippet(from: content), "key: value")
    }

    func testSnippet_whitespaceOnly_returnsEmptyString() {
        XCTAssertEqual(YAMLFileReader.makeSnippet(from: "   \n\n\t\n   "), "")
    }

    func testSnippet_internalBlankLines_preserved() {
        let content = "a: 1\n\nb: 2\n\nc: 3"
        let snippet = YAMLFileReader.makeSnippet(from: content)
        XCTAssertTrue(snippet.contains("\n\n"), "Internal blank lines must be preserved")
    }

    func testSnippet_veryLongSingleLine_notTruncated() {
        // A single line of 500 KB — still just 1 line, should not be truncated
        let content = "key: " + String(repeating: "v", count: 500_000)
        let snippet = YAMLFileReader.makeSnippet(from: content)
        XCTAssertFalse(snippet.hasSuffix("..."), "Single-line content must never be line-truncated")
        XCTAssertEqual(snippet.utf8.count, content.utf8.count)
    }

    // -------------------------------------------------------------------------
    // MARK: - makeSnippet: Real-world YAML Content
    // -------------------------------------------------------------------------

    func testSnippet_munkiPkginfo() {
        let yaml = """
        _metadata:
          creation_date: '2026-01-15T10:00:00Z'
          munki_version: 6.3.0
        blocking_applications:
          - Safari
          - Mail
        catalogs:
          - production
        category: Productivity
        description: A useful application
        display_name: My App
        installer_item_location: apps/MyApp-1.0.pkg
        minimum_os_version: '12.0'
        name: MyApp
        receipts:
          - installed_size: 45000
            packageid: com.example.MyApp
            version: '1.0'
        version: '1.0'
        """
        let snippet = YAMLFileReader.makeSnippet(from: yaml)
        XCTAssertTrue(snippet.contains("catalogs"))
        XCTAssertTrue(snippet.contains("production"))
        XCTAssertTrue(snippet.contains("munki_version"))
    }

    func testSnippet_ansiblePlaybook() {
        let yaml = """
        ---
        - name: Configure web servers
          hosts: webservers
          become: true
          vars:
            http_port: 80
            max_clients: 200
          tasks:
            - name: Install nginx
              ansible.builtin.package:
                name: nginx
                state: present
            - name: Start nginx service
              ansible.builtin.service:
                name: nginx
                state: started
                enabled: true
          handlers:
            - name: Restart nginx
              ansible.builtin.service:
                name: nginx
                state: restarted
        """
        let snippet = YAMLFileReader.makeSnippet(from: yaml)
        XCTAssertTrue(snippet.contains("webservers"))
        XCTAssertTrue(snippet.contains("nginx"))
        XCTAssertTrue(snippet.contains("handlers"))
    }

    func testSnippet_kubernetesDeployment() {
        let yaml = """
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: nginx-deployment
          labels:
            app: nginx
        spec:
          replicas: 3
          selector:
            matchLabels:
              app: nginx
          template:
            metadata:
              labels:
                app: nginx
            spec:
              containers:
              - name: nginx
                image: nginx:1.14.2
                ports:
                - containerPort: 80
                resources:
                  limits:
                    cpu: "500m"
                    memory: "128Mi"
                  requests:
                    cpu: "250m"
                    memory: "64Mi"
        """
        let snippet = YAMLFileReader.makeSnippet(from: yaml)
        XCTAssertTrue(snippet.contains("Deployment"))
        XCTAssertTrue(snippet.contains("replicas: 3"))
        XCTAssertTrue(snippet.contains("cpu: \"500m\""))
    }

    func testSnippet_githubActionsWorkflow() {
        let yaml = """
        name: CI
        on:
          push:
            branches: [main]
          pull_request:
            branches: [main]
        jobs:
          test:
            runs-on: macos-15
            steps:
              - uses: actions/checkout@v4
              - name: Build and Test
                run: xcodebuild test
        """
        let snippet = YAMLFileReader.makeSnippet(from: yaml)
        XCTAssertTrue(snippet.contains("runs-on: macos-15"))
        XCTAssertTrue(snippet.contains("xcodebuild test"))
    }

    func testSnippet_yamlWithComments() {
        let yaml = """
        # Main configuration
        server:
          # Host address
          host: localhost  # change in production
          port: 8080
        # Database settings
        database:
          url: postgres://localhost/mydb
        """
        let snippet = YAMLFileReader.makeSnippet(from: yaml)
        XCTAssertTrue(snippet.contains("# Main configuration"))
        XCTAssertTrue(snippet.contains("host: localhost"))
        XCTAssertTrue(snippet.contains("# change in production"))
    }

    func testSnippet_yamlMultiDocument() {
        let yaml = """
        ---
        document: first
        key: value1
        ---
        document: second
        key: value2
        ...
        """
        let snippet = YAMLFileReader.makeSnippet(from: yaml)
        XCTAssertTrue(snippet.contains("---"))
        XCTAssertTrue(snippet.contains("first"))
        XCTAssertTrue(snippet.contains("second"))
    }

    func testSnippet_yamlAnchorsAndAliases() {
        let yaml = """
        defaults: &defaults
          timeout: 30
          retries: 3
        production:
          <<: *defaults
          host: prod.example.com
        staging:
          <<: *defaults
          host: staging.example.com
        """
        let snippet = YAMLFileReader.makeSnippet(from: yaml)
        XCTAssertTrue(snippet.contains("&defaults"))
        XCTAssertTrue(snippet.contains("*defaults"))
        XCTAssertTrue(snippet.contains("<<:"))
    }

    func testSnippet_yamlBlockScalars() {
        let yaml = """
        literal_block: |
          line one
          line two
          line three
        folded_block: >
          this is a
          folded string
        tilde_null: ~
        explicit_null: null
        """
        let snippet = YAMLFileReader.makeSnippet(from: yaml)
        XCTAssertTrue(snippet.contains("literal_block: |"))
        XCTAssertTrue(snippet.contains("folded_block: >"))
        XCTAssertTrue(snippet.contains("tilde_null: ~"))
    }

    func testSnippet_unicodeKeysAndValues() {
        let yaml = "名前: 山田太郎\n年齢: 30\n職業: エンジニア\nplace: 東京都"
        let snippet = YAMLFileReader.makeSnippet(from: yaml)
        XCTAssertTrue(snippet.contains("名前"))
        XCTAssertTrue(snippet.contains("山田太郎"))
        XCTAssertTrue(snippet.contains("東京都"))
    }

    func testSnippet_windowsCRLFEditedYAML() {
        // Simulate a YAML file saved by Notepad or similar Windows editor
        let yaml = "---\r\nname: MyApp\r\nversion: '1.0'\r\ncatalogs:\r\n  - testing\r\n  - production\r\n"
        let snippet = YAMLFileReader.makeSnippet(from: yaml)
        XCTAssertFalse(snippet.contains("\r"), "Windows CRLF must be normalised")
        XCTAssertTrue(snippet.contains("catalogs"))
        XCTAssertTrue(snippet.contains("production"))
    }

    func testSnippet_deeplyNestedYaml() {
        // 20-levels deep — valid structure for Kubernetes / Helm charts
        var yaml = "level1:\n"
        for depth in 2...20 {
            yaml += String(repeating: "  ", count: depth - 1) + "level\(depth):\n"
        }
        yaml += String(repeating: "  ", count: 20) + "value: deep_leaf"
        let snippet = YAMLFileReader.makeSnippet(from: yaml)
        XCTAssertTrue(snippet.contains("level1:"))
        XCTAssertTrue(snippet.contains("value: deep_leaf"))
    }

    // -------------------------------------------------------------------------
    // MARK: - Integration: Preview Content
    // -------------------------------------------------------------------------

    func testPreview_truncationBannerContainsCorrectMBCount() throws {
        let targetMB: UInt64 = 2
        let limitMB: UInt64 = 1
        let data = Data(repeating: UInt8(ascii: "k"), count: Int(targetMB * 1024 * 1024))
        let url = try writeTempFile(name: "preview-large.yaml", data: data)
        let result = try YAMLFileReader.read(fileAt: url, maxFileSize: limitMB * 1024 * 1024)
        guard case .truncated(_, let sizeMB) = result else { return XCTFail("Expected .truncated") }
        // Simulate what PreviewProvider renders
        let banner = "\n\n--- File truncated (\(sizeMB) MB exceeds 10 MB preview limit) ---"
        XCTAssertTrue(banner.contains("\(targetMB) MB"),
                      "Banner must contain the actual file size in MB")
    }

    func testPreview_outputIsValidUTF8Data() throws {
        let content = "key: value\n🐢: turtle\n日本語: テスト"
        let url = try writeTempFile(name: "utf8round.yaml", content: content)
        let result = try YAMLFileReader.read(fileAt: url)
        // The content must survive round-trip through Data(utf8) back to String
        let data = Data(result.content.utf8)
        XCTAssertNotNil(String(data: data, encoding: .utf8),
                        "Content must always be representable as valid UTF-8 Data")
    }

    func testPreview_truncatedOutputIsValidUTF8Data() throws {
        // Truncated content (even with potential boundary cuts) must be valid UTF-8 Data
        let line = String(repeating: "あ", count: 30) + "\n"
        let count = Int(smallLimit / UInt64(line.utf8.count)) + 5
        let url = try writeTempFile(name: "truncated-utf8.yaml", content: String(repeating: line, count: count))
        let result = try YAMLFileReader.read(fileAt: url, maxFileSize: smallLimit)
        let data = Data(result.content.utf8)
        XCTAssertNotNil(String(data: data, encoding: .utf8))
    }
}

