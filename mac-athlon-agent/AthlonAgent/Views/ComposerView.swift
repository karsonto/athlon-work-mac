import SwiftUI

// MARK: - Composer View
struct ComposerView: View {
    @EnvironmentObject var appState: AppState
    @Binding var messageText: String
    @Binding var attachedImages: [ImageAttachment]
    @Binding var attachedFiles: [String]

    @State private var showAtCompletion: Bool = false
    @State private var atFilterText: String = ""
    @State private var atSelectedIndex: Int = 0
    @State private var composerHeight: CGFloat = 48

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    // Computed @-completion items
    private var atCompletionItems: [(type: String, icon: String, text: String, detail: String)] {
        var items: [(type: String, icon: String, text: String, detail: String)] = []

        // File items from workspace
        for file in appState.workspaceFiles.prefix(15) {
            let name = file.name
            if atFilterText.isEmpty || name.localizedCaseInsensitiveContains(atFilterText) {
                items.append(("文件", file.isDirectory ? "folder" : "doc", name, file.path))
            }
        }

        // Skill items
        for skill in appState.skills {
            let name = skill.name
            if atFilterText.isEmpty || name.localizedCaseInsensitiveContains(atFilterText) {
                items.append(("技能", "sparkles", name, skill.description ?? ""))
            }
        }

        // Image files
        for img in attachedImages {
            let name = "@" + img.fileName
            if atFilterText.isEmpty || name.localizedCaseInsensitiveContains(atFilterText) {
                items.append(("图片", "photo", img.fileName, "已添加"))
            }
        }

        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            // @-Completion popup
            if showAtCompletion && !atCompletionItems.isEmpty {
                atCompletionPopup
            }

            Divider()
                .foregroundColor(colors.border)

            // File attachments
            if !attachedFiles.isEmpty {
                fileAttachmentsRow
            }

            // Image attachments
            if !attachedImages.isEmpty {
                imageAttachmentsRow
            }

            // Main input area
            mainInputArea
        }
        .background(colors.panel)
        .onChange(of: messageText) { newValue in
            handleAtTrigger(newValue)
        }
    }

    // MARK: - @-Completion Popup
    private var atCompletionPopup: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(atCompletionItems.enumerated()), id: \.offset) { index, item in
                        AtCompletionRow(
                            type: item.type,
                            icon: item.icon,
                            text: item.text,
                            detail: item.detail,
                            isSelected: index == atSelectedIndex
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            insertAtCompletion(at: index)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 240)

            // Footer hint
            HStack {
                Text("↑↓ 导航 · Enter 选择 · Esc 关闭")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#52525B"))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(hex: "#1A1A1E"))
        }
        .background(Color(hex: "#18181B"))
        .overlay(
            Rectangle().fill(Color(hex: "#3F3F46")).frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - File Attachments Row
    private var fileAttachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachedFiles, id: \.self) { file in
                    FileChip(name: file) {
                        attachedFiles.removeAll { $0 == file }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Image Attachments Row
    private var imageAttachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachedImages) { img in
                    ImageAttachmentChip(image: img) {
                        attachedImages.removeAll { $0.id == img.id }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Main Input Area
    private var mainInputArea: some View {
        VStack(spacing: 0) {
            // Markdown toolbar
            MarkdownToolbar { snippet in
                messageText += snippet
            }

            // Text input
            HStack(alignment: .bottom, spacing: 8) {
                // @ button
                Button(action: { showAtCompletion.toggle() }) {
                    Text("@")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(showAtCompletion ? Color.white : colors.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(showAtCompletion ? colors.accent : colors.accent.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .help("输入 @ 选择文件、技能或上下文 (⌘@)")

                // Text editor (NSTextView wrapped for Enter handling)
                ComposerTextView(
                    text: $messageText,
                    height: $composerHeight,
                    onSend: sendMessage,
                    minimumHeight: 48,
                    maximumHeight: LayoutMetrics.composerMaxHeight
                )
                .frame(height: composerHeight)

                // Send / Stop button
                if appState.isAgentRunning {
                    Button(action: { /* stop agent */ }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Color(hex: "#EF4444"))
                    }
                    .buttonStyle(.plain)
                    .help("停止生成")
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(
                                messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && attachedImages.isEmpty
                                ? colors.subtleText : colors.accent
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                    .help("发送消息 (Enter)")
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedImages.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Bottom info bar
            HStack {
                // Image attachment button
                Button(action: addImageAttachment) {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 11))
                        Text("添加图片")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(colors.subtleText)

                // File attachment button
                Button(action: addFileAttachment) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 11))
                        Text("添加文件")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(colors.subtleText)
                    .padding(.leading, 8)

                Spacer()

                // Character count
                if !messageText.isEmpty {
                    Text("\(messageText.count) 字符")
                        .font(.system(size: 10))
                        .foregroundColor(colors.subtleText)
                }

                Text("Enter 发送 · Shift+Enter 换行 · ⌘@ 补全")
                    .font(.system(size: 10))
                    .foregroundColor(colors.subtleText)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    // MARK: - @-Trigger Detection
    private func handleAtTrigger(_ text: String) {
        // Find last @ position in current line
        guard let lastNewline = text.lastIndex(of: "\n") else {
            // Single line: check from start
            detectAtFrom(text, startIndex: text.startIndex)
            return
        }

        let afterNewline = text.index(after: lastNewline)
        let currentLine = String(text[afterNewline...])
        detectAtFrom(currentLine, startIndex: currentLine.startIndex)
    }

    private func detectAtFrom(_ line: String, startIndex: String.Index) {
        if let lastAt = line.lastIndex(of: "@") {
            // Check if @ is at word start (preceded by space or start of line)
            let beforeAt = line[..<lastAt]
            if beforeAt.isEmpty || beforeAt.last == " " || beforeAt.last == "\n" {
                let afterAt = String(line[line.index(after: lastAt)...])
                // Only show if filter is non-empty and not a space
                atFilterText = afterAt
                showAtCompletion = true
                atSelectedIndex = 0
                return
            }
        }
        showAtCompletion = false
        atFilterText = ""
    }

    private func insertAtCompletion(at index: Int) {
        guard index < atCompletionItems.count else { return }
        let item = atCompletionItems[index]

        // Replace @filterText with selected item
        if let lastAt = messageText.lastIndex(of: "@") {
            let prefix = String(messageText[..<lastAt])
            messageText = prefix + "@" + item.text + " "
        }

        showAtCompletion = false
        atFilterText = ""
    }

    // MARK: - Actions
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedImages.isEmpty else { return }
        appState.sendMessage(text)
        messageText = ""
        attachedImages = []
        attachedFiles = []
        showAtCompletion = false
    }

    private func addImageAttachment() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                let attachment = ImageAttachment(
                    id: UUID().uuidString,
                    fileName: url.lastPathComponent,
                    originalURL: url,
                    thumbnailData: data,
                    originalData: data
                )
                attachedImages.append(attachment)
            }
        }
    }

    private func addFileAttachment() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.text, .sourceCode, .plainText, .data,
                                       .init(filenameExtension: "md") ?? .text,
                                       .init(filenameExtension: "json") ?? .text,
                                       .init(filenameExtension: "yaml") ?? .text,
                                       .init(filenameExtension: "yml") ?? .text,
                                       .init(filenameExtension: "xml") ?? .text]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                attachedFiles.append(url.lastPathComponent)
            }
        }
    }
}

// MARK: - At-Completion Row
struct AtCompletionRow: View {
    let type: String
    let icon: String
    let text: String
    let detail: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Type badge
            Text(type)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(typeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(typeColor.opacity(0.15)))

            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#A1A1AA"))

            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#F4F4F5"))
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#71717A"))
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Text("↩")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6366F1"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color(hex: "#6366F1").opacity(0.1) : Color.clear)
    }

    private var typeColor: Color {
        switch type {
        case "文件": return Color(hex: "#3B82F6")
        case "技能": return Color(hex: "#A78BFA")
        case "图片": return Color(hex: "#F59E0B")
        default: return Color(hex: "#A1A1AA")
        }
    }
}

// MARK: - Image Attachment Chip
struct ImageAttachmentChip: View {
    let image: ImageAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if let data = image.thumbnailData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 36)
                    .clipped()
                    .cornerRadius(4, corners: [.topLeft, .bottomLeft])
            } else {
                Image(systemName: "photo")
                    .frame(width: 48, height: 36)
                    .background(Color(hex: "#27272A"))
                    .cornerRadius(4, corners: [.topLeft, .bottomLeft])
            }

            VStack(spacing: 2) {
                Text(image.fileName)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#D4D4D8"))
                    .lineLimit(1)
                    .frame(width: 72)
                Text(formatSize(image.originalData?.count ?? 0))
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#71717A"))
            }
            .padding(.horizontal, 6)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(hex: "#A1A1AA"))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(hex: "#1E1E24"))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(hex: "#3F3F46"), lineWidth: 1)
                )
        )
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Composer NSViewRepresentable (NSTextView for Enter handling)
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let onSend: () -> Void
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        // Inset to remove default NSTextView padding
        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = NSColor(hex: "#F4F4F5")
        textView.insertionPointColor = NSColor(hex: "#6366F1")
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.lineFragmentPadding = 0

        // Background styling
        textView.wantsLayer = true
        textView.layer?.backgroundColor = NSColor(hex: "#1A1A1E").cgColor
        textView.layer?.cornerRadius = 8
        textView.layer?.borderWidth = 1
        textView.layer?.borderColor = NSColor(hex: "#3F3F46").cgColor

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.textView = textView
        context.coordinator.scrollView = nsView

        // Only update text if different from current (prevent loop)
        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.selectedRange = selectedRange
        }

        // Update text color for dark/light
        textView.textColor = NSColor(hex: "#F4F4F5")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $height, onSend: onSend, minimumHeight: minimumHeight, maximumHeight: maximumHeight)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var height: CGFloat
        let onSend: () -> Void
        let minimumHeight: CGFloat
        let maximumHeight: CGFloat
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(text: Binding<String>, height: Binding<CGFloat>, onSend: @escaping () -> Void, minimumHeight: CGFloat, maximumHeight: CGFloat) {
            self._text = text
            self._height = height
            self.onSend = onSend
            self.minimumHeight = minimumHeight
            self.maximumHeight = maximumHeight
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            text = textView.string
            updateHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Check for Shift+Enter (shift key down)
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) {
                    // Allow default newline behavior
                    return false
                } else {
                    // Enter = send
                    onSend()
                    return true
                }
            }
            return false
        }

        private func updateHeight() {
            guard let textView = textView, let scrollView = scrollView else { return }

            // Calculate natural height
            textView.sizeToFit()
            let naturalHeight = max(textView.frame.height + 8, minimumHeight)
            let clamped = min(naturalHeight, maximumHeight)

            DispatchQueue.main.async {
                self.height = clamped
                // Enable vertical scrolling when maxed out
                scrollView.hasVerticalScroller = naturalHeight > self.maximumHeight
            }
        }
    }
}

// MARK: - NSColor Hex Helper
extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

// MARK: - RoundedCorner Shape
extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = CGMutablePath()

        let topLeft = corners.contains(.topLeft) ? radius : 0
        let topRight = corners.contains(.topRight) ? radius : 0
        let bottomLeft = corners.contains(.bottomLeft) ? radius : 0
        let bottomRight = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRight),
                    radius: topRight)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY),
                    radius: bottomRight)
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft),
                    radius: bottomLeft)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + topLeft, y: rect.minY),
                    radius: topLeft)

        return Path(path)
    }
}
