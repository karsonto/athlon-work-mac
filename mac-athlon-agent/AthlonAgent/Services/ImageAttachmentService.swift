import Foundation
import AppKit

// MARK: - Image Attachment Service
/// Handles image selection, thumbnail generation, encoding, and attachment lifecycle.
class ImageAttachmentService: ObservableObject {
    @Published var attachments: [ImageAttachment] = []
    @Published var isLoading = false

    func selectImages(
        from urls: [URL],
        thumbnailSize: CGSize = CGSize(width: 320, height: 240),
        compression: CGFloat = 0.8
    ) {
        isLoading = true
        defer { isLoading = false }

        for url in urls {
            guard let originalData = try? Data(contentsOf: url) else { continue }

            let thumbnailData = generateThumbnail(from: originalData, maxSize: thumbnailSize, compression: compression)

            let attachment = ImageAttachment(
                id: UUID().uuidString,
                fileName: url.lastPathComponent,
                originalURL: url,
                thumbnailData: thumbnailData,
                originalData: originalData
            )
            attachments.append(attachment)
        }
    }

    func removeAttachment(_ id: String) {
        attachments.removeAll { $0.id == id }
    }

    func clearAll() {
        attachments = []
    }

    // MARK: - Thumbnail Generation
    private func generateThumbnail(
        from imageData: Data,
        maxSize: CGSize,
        compression: CGFloat
    ) -> Data? {
        guard let image = NSImage(data: imageData) else { return nil }

        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        // Calculate scaled size maintaining aspect ratio
        let scale = min(maxSize.width / originalSize.width, maxSize.height / originalSize.height, 1.0)
        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        // Create thumbnail
        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                    from: NSRect(origin: .zero, size: originalSize),
                    operation: .copy,
                    fraction: 1.0)
        thumbnail.unlockFocus()

        // Encode as JPEG
        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return nil }

        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compression])
    }

    // MARK: - Base64 Encode (for API submission)
    func base64Encode(_ data: Data, mimeType: String = "image/jpeg") -> String {
        let base64 = data.base64EncodedString()
        return "data:\(mimeType);base64,\(base64)"
    }

    func encodeAllAsBase64() -> [(name: String, dataURI: String)] {
        attachments.compactMap { attachment in
            guard let data = attachment.originalData else { return nil }
            let ext = (attachment.fileName as NSString).pathExtension.lowercased()
            let mimeType = mimeTypeFor(extension: ext)
            return (attachment.fileName, base64Encode(data, mimeType: mimeType))
        }
    }

    private func mimeTypeFor(extension ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return "image/png"
        }
    }

    // MARK: - Size Helpers
    func totalSize() -> Int {
        attachments.compactMap { $0.originalData?.count }.reduce(0, +)
    }

    func formattedTotalSize() -> String {
        let bytes = totalSize()
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
