import Foundation

struct FileToolsPolicySection: IEnvironmentPromptSection {
    let order = 450
    let placement: PromptSectionPlacement = .static

    func append(to builder: inout String, context: EnvironmentPromptContext) {
        builder += "File tools:\n"
        builder += "- For large files, use grep_files or glob_files to locate content before file_read.\n"
        builder += "- Use file_read with offset and limit to read in chunks; do not assume a single read covers the whole file.\n"
        builder += "- When file_read returns truncated: true or a next_offset in the meta footer, continue with that offset.\n"
        builder += "- file_read line output uses N| prefixes for display only; file_edit old_text must match disk content without those prefixes.\n"
        builder += "- Paths from file_list, glob_files, or grep_files are exact on-disk names. Copy them character-for-character into file_read, file_write, file_edit, and execute_command.\n"
        builder += "- Never insert spaces between Latin letters and CJK characters inside a filename (e.g. disk has GMT沙盒AI演示.mp4 — not \"GMT 沙盒 AI 演示.mp4\").\n"
        builder += "\n"
    }
}
