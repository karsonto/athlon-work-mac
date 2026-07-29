import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    var isRunning: Bool = false
    var height: CGFloat = AppLayoutMetrics.composerDefaultHeight
    var maxContentWidth: CGFloat = AppLayoutMetrics.composerMaxContentWidth
    var placeholder: String = "Plan, Build, / for skills, @ for context"
    var language: String = "zh-CN"
    @Binding var harnessMode: ComposerHarnessMode
    var attachments: ComposerAttachmentStore? = nil
    /// Hero empty-state uses a taller, quieter chrome (Cursor-like).
    var style: ComposerChromeStyle = .docked
    var chrome: UiChromeColors? = nil
    var onSend: () -> Void
    var onStop: (() -> Void)?
    var onMicTap: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    enum ComposerChromeStyle {
        case hero
        case docked
    }

    private var colors: UiChromeColors {
        chrome ?? DarkAppThemePalette.create().chrome
    }

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !(attachments?.isEmpty ?? true)
        return (hasText || hasImages) && !isRunning
    }

    private var minTextHeight: CGFloat {
        style == .hero ? AppLayoutMetrics.composerEmptyTextMinHeight : 56
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .hero ? 14 : 10) {
            if let attachments, !attachments.images.isEmpty {
                attachmentChips(attachments)
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty && !isFocused {
                    Text(placeholder)
                        .font(.system(size: style == .hero ? 15 : 14))
                        .foregroundStyle(colors.subtleText.color.opacity(0.85))
                        .padding(.horizontal, style == .hero ? 2 : 4)
                        .padding(.vertical, style == .hero ? 4 : 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.system(size: style == .hero ? 15 : 14))
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: minTextHeight)
                    .foregroundStyle(colors.text.color)
                    .onKeyPress { press in
                        if press.key == .return {
                            if press.modifiers.contains(.shift) {
                                return .ignored
                            }
                            if canSend {
                                onSend()
                                return .handled
                            }
                        }
                        return .ignored
                    }
            }
            .frame(maxHeight: .infinity)

            bottomBar
        }
        .padding(style == .hero ? EdgeInsets(top: 16, leading: 18, bottom: 12, trailing: 18) : EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: maxContentWidth)
        .frame(minHeight: height)
        .background(
            RoundedRectangle(cornerRadius: style == .hero ? 24 : 14, style: .continuous)
                .fill(colors.composer.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: style == .hero ? 24 : 14, style: .continuous)
                .strokeBorder(colors.composerBorder.color.opacity(0.9), lineWidth: 1)
        )
        .shadow(
            color: style == .hero ? Color.clear : Color.clear,
            radius: 0,
            y: 0
        )
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                attachments?.pickImagesFromPanel()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.subtleText.color)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(colors.panelAlt.color.opacity(0.8))
                    )
            }
            .buttonStyle(.plain)
            .help(L10n.t("composer.attach", language: language))
            .disabled(attachments == nil)

            Menu {
                ForEach(ComposerHarnessMode.allCases) { mode in
                    Button {
                        harnessMode = mode
                    } label: {
                        if harnessMode == mode {
                            Label(mode.title(language: language), systemImage: "checkmark")
                        } else {
                            Text(mode.title(language: language))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(modeDotColor)
                        .frame(width: 7, height: 7)
                    Text(modeLabel)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(0.7)
                }
                .foregroundStyle(colors.textSecondary.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(colors.panelAlt.color.opacity(0.65))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 0)

            if isRunning {
                Button(action: { onStop?() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colors.text.color)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(colors.danger.color.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help(L10n.t("composer.stop", language: language))
            } else if canSend {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(colors.accent.color))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .help(L10n.t("composer.send", language: language))
            } else {
                Button {
                    onMicTap?()
                    _ = attachments?.pasteFromClipboard()
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(colors.subtleText.color)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(L10n.t("composer.micHint", language: language))
            }
        }
    }

    private var modeLabel: String {
        if harnessMode == .agent {
            return L10n.t("composer.mode.auto", language: language)
        }
        return harnessMode.title(language: language)
    }

    private var modeDotColor: Color {
        switch harnessMode {
        case .agent: return Color(red: 0.35, green: 0.55, blue: 1.0)
        case .ask: return colors.warning.color
        case .plan: return colors.accent.color
        case .coding: return colors.success.color
        }
    }

    private func attachmentChips(_ store: ComposerAttachmentStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.images) { image in
                    HStack(spacing: 6) {
                        Text(image.fileName)
                            .font(.caption)
                            .lineLimit(1)
                        Button {
                            store.remove(id: image.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(colors.panelAlt.color))
                    .foregroundStyle(colors.textSecondary.color)
                }
            }
        }
    }
}

#Preview {
    ComposerView(
        text: .constant(""),
        harnessMode: .constant(.agent),
        style: .hero,
        onSend: {}
    )
    .padding()
    .frame(width: 720, height: 220)
    .preferredColorScheme(.dark)
}
