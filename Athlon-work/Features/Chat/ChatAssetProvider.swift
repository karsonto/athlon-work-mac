import Foundation

/// Resolves a directory containing Chat WebView assets (`highlight.min.js`, etc.).
/// Prefers `Bundle.main/Resources/Chat`, then copies from the development source tree when needed.
enum ChatAssetProvider {
    static let requiredFiles: [String] = [
        "highlight.min.js",
        "marked.min.js",
        "chat-timeline.js",
        "chat-shell.css",
        "github.min.css",
        "github-dark.min.css",
        "chat-fixture-events.json",
    ]

    /// Returns a directory URL that contains all chat assets, suitable as WKWebView `baseURL`.
    static func ensureChatResourceDirectory() throws -> URL {
        #if DEBUG
        if let dev = developmentSourceChatDirectory(), hasAllRequiredAssets(at: dev) {
            let cacheRoot = try cacheDirectory()
            try syncAssets(into: cacheRoot, preferredRoot: dev)
            return cacheRoot
        }
        #endif

        if let bundled = chatResourceDirectoryIfPresent(), hasAllRequiredAssets(at: bundled) {
            return bundled
        }

        let cacheRoot = try cacheDirectory()
        try syncAssets(into: cacheRoot)
        return cacheRoot
    }

    /// Locates Chat resources without copying (bundle or source tree).
    static func chatResourceDirectory() -> URL? {
        if let bundled = chatResourceDirectoryIfPresent(), hasAllRequiredAssets(at: bundled) {
            return bundled
        }
        return developmentSourceChatDirectory()
    }

    static func fixtureEventsURL() -> URL? {
        if let dir = try? ensureChatResourceDirectory() {
            let url = dir.appendingPathComponent("chat-fixture-events.json")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if let url = Bundle.main.url(forResource: "chat-fixture-events", withExtension: "json", subdirectory: "Chat") {
            return url
        }
        if let url = Bundle.main.url(forResource: "chat-fixture-events", withExtension: "json") {
            return url
        }
        return developmentSourceChatDirectory()?.appendingPathComponent("chat-fixture-events.json")
    }

    // MARK: - Internals

    private static func chatResourceDirectoryIfPresent() -> URL? {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("Chat"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }
        if let url = Bundle.main.url(forResource: "Chat", withExtension: nil) {
            return url
        }
        // Synchronized root may flatten Resources/Chat into the bundle root.
        if let highlight = Bundle.main.url(forResource: "highlight", withExtension: "min.js"),
           let parent = Optional(highlight.deletingLastPathComponent()),
           hasAllRequiredAssets(at: parent) {
            return parent
        }
        return nil
    }

    private static func developmentSourceChatDirectory() -> URL? {
        // Features/Chat/ChatAssetProvider.swift → ../../Resources/Chat
        let thisFile = URL(fileURLWithPath: #filePath)
        let candidate = thisFile
            .deletingLastPathComponent() // Chat
            .deletingLastPathComponent() // Features
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Chat", isDirectory: true)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    private static func cacheDirectory() throws -> URL {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support
            .appendingPathComponent("AthlonAgent", isDirectory: true)
            .appendingPathComponent("ChatAssets", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func syncAssets(into destination: URL, preferredRoot: URL? = nil) throws {
        let fm = FileManager.default
        var sources = collectSourceURLs()
        if let preferredRoot {
            for name in requiredFiles {
                let url = preferredRoot.appendingPathComponent(name)
                if fm.fileExists(atPath: url.path) {
                    sources[name] = url
                }
            }
        }
        for name in requiredFiles {
            guard let source = sources[name] else {
                throw ChatAssetError.missingAsset(name)
            }
            let dest = destination.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path),
               let srcDate = modificationDate(of: source),
               let dstDate = modificationDate(of: dest),
               srcDate <= dstDate {
                continue
            }
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: source, to: dest)
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private static func collectSourceURLs() -> [String: URL] {
        var map: [String: URL] = [:]
        let searchRoots: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("Chat"),
            Bundle.main.resourceURL,
            developmentSourceChatDirectory(),
        ].compactMap { $0 }

        for root in searchRoots {
            for name in requiredFiles where map[name] == nil {
                let url = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    map[name] = url
                }
            }
        }

        for name in requiredFiles where map[name] == nil {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Chat")
                ?? Bundle.main.url(forResource: base, withExtension: ext) {
                map[name] = url
            }
        }
        return map
    }

    private static func hasAllRequiredAssets(at directory: URL) -> Bool {
        let fm = FileManager.default
        return requiredFiles.allSatisfy { name in
            fm.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
    }
}

enum ChatAssetError: Error, LocalizedError {
    case missingAsset(String)
    case resourceDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .missingAsset(let name):
            return "Missing chat asset: \(name)"
        case .resourceDirectoryUnavailable:
            return "Chat resource directory is unavailable"
        }
    }
}
