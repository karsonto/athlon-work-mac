import Foundation

enum MemoryFlushResult {
    case skipped
    case failed(String)
    case success(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var extracted: String? {
        if case let .success(text) = self { return text }
        return nil
    }

    var errorMessage: String? {
        if case let .failed(msg) = self { return msg }
        return nil
    }
}
