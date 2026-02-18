import AppKit
import OSLog
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.yamlquicklook.YamlQuickLook", category: "thumbnail")

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let content = try YAMLFileReader.read(fileAt: request.fileURL).content
            handler(makeThumbnailReply(for: request, content: content), nil)
        } catch {
            logger.error("Failed to read file for thumbnail: \(error.localizedDescription, privacy: .public)")
            handler(nil, error)
        }
    }

    private func makeThumbnailReply(for request: QLFileThumbnailRequest, content: String) -> QLThumbnailReply {
        let baseSize = max(request.maximumSize.width, request.maximumSize.height)
        let contextSize = CGSize(width: baseSize, height: baseSize)

        return QLThumbnailReply(contextSize: contextSize, currentContextDrawing: { [weak self] () -> Bool in
            guard let self, let context = NSGraphicsContext.current?.cgContext else { return false }
            self.drawThumbnail(in: context, size: contextSize, scale: request.scale, content: content)
            return true
        })
    }

    private func drawThumbnail(in context: CGContext, size: CGSize, scale: CGFloat, content: String) {
        context.saveGState()
        defer { context.restoreGState() }

        context.scaleBy(x: scale, y: scale)

        let canvasSize = CGSize(width: size.width / scale, height: size.height / scale)
        let canvasRect = CGRect(origin: .zero, size: canvasSize)

        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(canvasRect)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        drawPlainPreview(in: canvasRect.insetBy(dx: 10, dy: 10), content: content)
    }

    private func drawPlainPreview(in rect: CGRect, content: String) {
        let snippet = YAMLFileReader.makeSnippet(from: content)
        let textRect = rect.insetBy(dx: 4, dy: 6)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.lineSpacing = 1.5

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        NSAttributedString(string: snippet, attributes: attributes).draw(in: textRect)
    }
}
