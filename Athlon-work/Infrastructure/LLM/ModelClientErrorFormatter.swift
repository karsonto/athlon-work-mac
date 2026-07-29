import Foundation

enum ModelClientErrorFormatter {
    static func userFacingMessage(for error: Error, endpoint: String) -> String {
        if let modelError = error as? AgentModelClientError {
            return modelError.localizedDescription
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost:
                let host = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? endpoint
                return "无法解析模型服务器主机名「\(host)」。请检查设置中的 Endpoint 是否正确，以及本机网络/DNS 是否正常。"
            case .notConnectedToInternet:
                return "未连接到互联网。请检查网络后重试。"
            case .timedOut:
                return "连接模型服务超时。请检查 Endpoint 或稍后重试。"
            case .cannotConnectToHost:
                let host = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? endpoint
                return "无法连接到「\(host)」。请确认服务地址与端口可用。"
            case .secureConnectionFailed:
                return "HTTPS 连接失败。请检查 Endpoint 是否使用正确的 https 地址。"
            default:
                return "网络错误 (\(urlError.code.rawValue)): \(urlError.localizedDescription)"
            }
        }

        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return userFacingMessage(for: URLError(_nsError: ns), endpoint: endpoint)
        }

        return error.localizedDescription
    }
}
