import AppKit
import Foundation
import UniformTypeIdentifiers

/// Pending composer image attachments (paste / file picker).
@Observable
@MainActor
final class ComposerAttachmentStore {
    struct PendingImage: Identifiable, Hashable {
        let id: String
        var fileName: String
        var mimeType: String
        var dataURL: String
    }

    private(set) var images: [PendingImage] = []

    var isEmpty: Bool { images.isEmpty }

    func clear() {
        images.removeAll()
    }

    @discardableResult
    func addImage(data: Data, fileName: String, mimeType: String) -> Bool {
        guard !data.isEmpty else { return false }
        let base64 = data.base64EncodedString()
        let dataURL = "data:\(mimeType);base64,\(base64)"
        let item = PendingImage(
            id: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            fileName: fileName,
            mimeType: mimeType,
            dataURL: dataURL
        )
        images.append(item)
        return true
    }

    func remove(id: String) {
        images.removeAll { $0.id == id }
    }

    func pasteFromClipboard() -> Bool {
        let pb = NSPasteboard.general
        if let tiff = pb.data(forType: .tiff),
           let image = NSImage(data: tiff),
           let png = image.pngData() {
            return addImage(data: png, fileName: "paste.png", mimeType: "image/png")
        }
        if let png = pb.data(forType: .png) {
            return addImage(data: png, fileName: "paste.png", mimeType: "image/png")
        }
        return false
    }

    func pickImagesFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = url.pathExtension.lowercased()
            let mime: String
            switch ext {
            case "jpg", "jpeg": mime = "image/jpeg"
            case "gif": mime = "image/gif"
            case "webp": mime = "image/webp"
            default: mime = "image/png"
            }
            _ = addImage(data: data, fileName: url.lastPathComponent, mimeType: mime)
        }
    }

    func toImageAttachments() -> [ImageAttachment] {
        images.map {
            ImageAttachment(fileName: $0.fileName, mimeType: $0.mimeType, dataUrl: $0.dataURL)
        }
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
