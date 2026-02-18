import Foundation
import QuickLookUI
import UniformTypeIdentifiers
import OSLog

/// The main Quick Look preview provider for YAML files.
@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, @unchecked Sendable, QLPreviewingController {
    private let logger = Logger(subsystem: "com.yamlquicklook.YamlQuickLook", category: "preview")

    func providePreview(for request: QLFilePreviewRequest, completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void) {
        do {
            let displayContent: String
            switch try YAMLFileReader.read(fileAt: request.fileURL) {
            case .complete(let text):
                displayContent = text
            case .truncated(let text, let sizeMB):
                displayContent = text + "\n\n--- File truncated (\(sizeMB) MB exceeds 10 MB preview limit) ---"
            }

            let reply = QLPreviewReply(dataOfContentType: .plainText, contentSize: CGSize(width: 800, height: 600)) { _ in
                Data(displayContent.utf8)
            }
            reply.stringEncoding = .utf8
            handler(reply, nil)
        } catch {
            logger.error("Failed to read YAML file: \(error.localizedDescription, privacy: .public)")
            handler(nil, error)
        }
    }
}
