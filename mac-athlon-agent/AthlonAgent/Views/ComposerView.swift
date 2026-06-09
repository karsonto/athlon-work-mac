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
    @State private var showSlashCompletion: Bool = false
    @State private var slashSelectedIndex: Int = 0
    @State private var slashFilterText: String = ""
    @State private var textAreaHeight: CGFloat = LayoutMetrics.composerTextMinHeight

    private var colors: ThemeColors {
        appState.theme == .dark ? .dark : .light
    }

    private var isComposerEmpty: Bool {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedImages.isEmpty
    }

    private var atCompletionItems: [(type: String, icon: String, text: String, detail: String)] {
        var items: [(type: String, icon: String, text: String, detail: String)] = []

        for file in appState.workspaceFiles.prefix(30) {
            let name = file.name
            if atFilterText.isEmpty || name.localizedCaseInsensitiveContains(atFilterText) {
                items.append(("文件", file.isDirectory ? "folder" : "doc", name, file.path))
            }
        }

        for skill in appState.skills {
            let name = skill.name
            if atFilterText.isEmpty || name.localizedCaseInsensitiveContains(atFilterText) {
                items.append(("技能", "sparkles", name, skill.description))
            }
        }

        return items.prefix(30).map { $0 }
    }

    private var slashCompletionItems: [SlashCompletionItem] {
        let commands: [SlashCompletionItem] = [
            SlashCompletionItem(name: "compact", description: "压缩当前会话上下文"),
            SlashCompletionItem(name: "help", description: "显示可用命令列表"),
        ]
        if slashFilterText.isEmpty {
            return commands
        }
        return commands.filter { $0.name.localizedCaseInsensitiveContains(slashFilterText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showAtCompletion && !atCompletionItems.isEmpty {
                atCompletionPopup
            }

            if showSlashCompletion && !slashCompletionItems.isEmpty {
                slashCompletionPopup
            }

            HStack {
                Spacer(minLength: 0)
                composerDock
                    .frame(maxWidth: LayoutMetrics.composerMaxWidth)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LayoutMetrics.composerOuterPaddingHorizontal)
            .padding(.vertical, LayoutMetrics.composerOuterPaddingVertical)
        }
        .onChange(of: messageText) { _, newValue in
            handleAtTrigger(newValue)
            handleSlashTrigger(newValue)
        }
    }

    // MARK: - Composer Dock
    private var composerDock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !attachedImages.isEmpty {
                imageAttachmentsRow
            }

            ComposerInputHost(
                text: $messageText,
                height: $textAreaHeight,
                onSend: sendMessage,
                minimumHeight: LayoutMetrics.composerTextMinHeight,
                maximumHeight: LayoutMetrics.composerMaxHeight - 80,
                textHex: appState.theme == .dark ? "#F4F4F5" : "#0F172A",
                accentHex: appState.theme == .dark ? "#2563EB" : "#0284C7"
            )
            .frame(maxWidth: .infinity, minHeight: textAreaHeight, maxHeight: textAreaHeight)
            .overlay(alignment: .topLeading) {
                if isComposerEmpty {
                    Text("Message Athlon — @ 文件 / 技能，Enter 发送")
                        .font(.system(size: LayoutMetrics.composerFontSize))
                        .foregroundColor(colors.disabledText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 12) {
                Button(action: addImageAttachment) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.subtleText)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colors.hoverNeutral)
                        )
                }
                .buttonStyle(.plain)
                .help("添加图片")

                Text(
                    appState.composerStatusMessage.isEmpty
                        ? "Enter 发送 · Shift+Enter 换行"
                        : appState.composerStatusMessage
                )
                    .font(.system(size: 11))
                    .foregroundColor(
                        appState.composerStatusMessage.isEmpty ? colors.disabledText : colors.accent
                    )
                    .lineLimit(2)

                Spacer()

                if appState.isBusy {
                    Button(action: { appState.stopAgent() }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: LayoutMetrics.sendButtonSize, height: LayoutMetrics.sendButtonSize)
                            .background(Circle().fill(colors.danger))
                    }
                    .buttonStyle(.plain)
                    .help("停止生成")
                }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: LayoutMetrics.sendButtonSize, height: LayoutMetrics.sendButtonSize)
                        .background(
                            Circle().fill(canSend ? colors.accent : colors.disabledText.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("发送消息 (Enter)")
            }

            // Composer hint
            Text("Enter 发送 · Shift+Enter 换行 · Cmd+V 粘贴图片 · @ 引用文件 · / 命令")
                .font(.system(size: 10))
                .foregroundColor(colors.disabledText)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.top, DesignTokens.Spacing.xs)
        }
        .padding(.horizontal, LayoutMetrics.composerInnerPaddingHorizontal)
        .padding(.vertical, LayoutMetrics.composerInnerPaddingVertical)
        .background(
            RoundedRectangle(cornerRadius: LayoutMetrics.composerCornerRadius)
                .fill(colors.composer)
                .overlay(
                    RoundedRectangle(cornerRadius: LayoutMetrics.composerCornerRadius)
                        .stroke(colors.border, lineWidth: 1)
                )
        )
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty
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
                            isSelected: index == atSelectedIndex,
                            colors: colors
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

            HStack {
                Text("↑↓ 导航 · Enter 选择 · Esc 关闭")
                    .font(.system(size: 10))
                    .foregroundColor(colors.disabledText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(colors.panelAlt)
        }
        .background(colors.panel)
        .overlay(Rectangle().fill(colors.border).frame(height: 1), alignment: .bottom)
        .padding(.horizontal, LayoutMetrics.composerOuterPaddingHorizontal)
    }

    private var slashCompletionPopup: some View {
        SlashCompletionPopover(
            items: slashCompletionItems,
            selectedIndex: slashSelectedIndex,
            onSelect: { item in
                applySlashCompletion(item)
            },
            colors: colors
        )
        .padding(.horizontal, DesignTokens.Spacing.md)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var imageAttachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachedImages) { img in
                    ImageAttachmentChip(image: img) {
                        attachedImages.removeAll { $0.id == img.id }
                    }
                }
            }
        }
    }

    private func handleAtTrigger(_ text: String) {
        guard let lastNewline = text.lastIndex(of: "\n") else {
            detectAtFrom(String(text))
            return
        }
        detectAtFrom(String(text[text.index(after: lastNewline)...]))
    }

    private func detectAtFrom(_ line: String) {
        if let lastAt = line.lastIndex(of: "@") {
            let beforeAt = line[..<lastAt]
            if beforeAt.isEmpty || beforeAt.last == " " || beforeAt.last == "\n" {
                atFilterText = String(line[line.index(after: lastAt)...])
                showAtCompletion = true
                atSelectedIndex = 0
                return
            }
        }
        showAtCompletion = false
        atFilterText = ""
    }

    private func handleSlashTrigger(_ text: String) {
        // Only trigger if text starts with / and has no spaces yet
        if text.hasPrefix("/") && !text.contains(" ") {
            let afterSlash = String(text.dropFirst())
            slashFilterText = afterSlash
            slashSelectedIndex = 0
            showSlashCompletion = true
        } else {
            showSlashCompletion = false
            slashFilterText = ""
        }
    }

    private func insertAtCompletion(at index: Int) {
        guard index < atCompletionItems.count else { return }
        let item = atCompletionItems[index]
        if let lastAt = messageText.lastIndex(of: "@") {
            let prefix = String(messageText[..<lastAt])
            let token = item.type == "技能" ? "@skill:\(item.text)" : "@\(item.text)"
            messageText = prefix + token + " "
        }
        showAtCompletion = false
        atFilterText = ""
    }

    private func applySlashCompletion(_ item: SlashCompletionItem) {
        // Find the "/" at the start of the message or after a newline
        if let slashRange = messageText.range(of: "/[^\\s]*$", options: .regularExpression) {
            messageText.replaceSubrange(slashRange, with: "/\(item.name) ")
        }
        showSlashCompletion = false
        slashFilterText = ""
    }

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
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP, .gif]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                attachedImages.append(ImageAttachment(
                    id: UUID().uuidString,
                    fileName: url.lastPathComponent,
                    filePath: url,
                    thumbnailData: data,
                    fileSize: Int64(data.count)
                ))
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
    let colors: ThemeColors

    var body: some View {
        HStack(spacing: 10) {
            Text(type)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(typeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(typeColor.opacity(0.15)))

            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(colors.subtleText)

            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colors.text)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(colors.subtleText)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Text("↩")
                    .font(.system(size: 10))
                    .foregroundColor(colors.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? colors.navActiveBg.opacity(0.5) : Color.clear)
    }

    private var typeColor: Color {
        switch type {
        case "文件": return colors.fileBadgeText
        case "技能": return colors.skillBadgeText
        default: return colors.subtleText
        }
    }
}

// MARK: - Image Attachment Chip
struct ImageAttachmentChip: View {
    let image: ImageAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if let data = image.thumbnailData, let nsImage = NSImage(data: data) {
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
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "#262628"))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#3F3F46"), lineWidth: 1))
        )
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
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
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRight), radius: topRight)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY), radius: bottomRight)
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft), radius: bottomLeft)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + topLeft, y: rect.minY), radius: topLeft)
        return Path(path)
    }
}
