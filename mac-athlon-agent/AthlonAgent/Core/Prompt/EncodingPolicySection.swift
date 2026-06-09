import Foundation

/// Informs the model about encoding and locale expectations.
struct EncodingPolicySection: IEnvironmentPromptSection {
    let order = 210
    let placement: PromptSectionPlacement = .static

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        builder += "Encoding and locale:\n"
        builder += "- Use UTF-8 for all file content, patches, command output, and text you write unless a tool result explicitly states another encoding.\n"
        builder += "- Assume workspace files and tool I/O are UTF-8; do not convert Chinese or other non-ASCII text to escape sequences or legacy code pages.\n"
        builder += "\n"
    }
}
