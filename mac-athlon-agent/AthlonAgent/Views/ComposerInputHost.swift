import AppKit
import SwiftUI

/// AppKit-backed composer input. Avoids SwiftUI TextEditor focus/layout issues on macOS.
struct ComposerInputHost: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let onSend: () -> Void
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat
    let textHex: String
    let accentHex: String

    func makeNSView(context: Context) -> ComposerInputContainer {
        let container = ComposerInputContainer(minimumHeight: minimumHeight)
        let textView = container.textView
        textView.delegate = context.coordinator
        textView.string = text
        applyTheme(to: textView)
        context.coordinator.attach(textView: textView, container: container)
        return container
    }

    func updateNSView(_ container: ComposerInputContainer, context: Context) {
        let textView = container.textView
        context.coordinator.parent = self
        context.coordinator.attach(textView: textView, container: container)

        if text.isEmpty, !textView.string.isEmpty {
            textView.string = ""
        }

        guard !context.coordinator.shouldSkipSync(for: textView) else {
            container.layoutTextView(proposedHeight: height)
            return
        }

        applyTheme(to: textView)
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            if selected.location <= textView.string.utf16.count {
                textView.setSelectedRange(selected)
            }
        }
        container.layoutTextView(proposedHeight: height)
    }

    @available(macOS 13.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ComposerInputContainer, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let resolvedHeight = max(min(height, maximumHeight), minimumHeight)
        nsView.layoutTextView(proposedHeight: resolvedHeight)
        return CGSize(width: width, height: resolvedHeight)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $height, onSend: onSend, minimumHeight: minimumHeight, maximumHeight: maximumHeight)
    }

    private func applyTheme(to textView: NSTextView) {
        textView.textColor = NSColor.fromHex(textHex)
        textView.insertionPointColor = NSColor.fromHex(accentHex)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerInputHost
        @Binding var text: String
        @Binding var height: CGFloat
        let onSend: () -> Void
        let minimumHeight: CGFloat
        let maximumHeight: CGFloat
        private weak var textView: NSTextView?
        private weak var container: ComposerInputContainer?

        init(text: Binding<String>, height: Binding<CGFloat>, onSend: @escaping () -> Void, minimumHeight: CGFloat, maximumHeight: CGFloat) {
            _text = text
            _height = height
            self.onSend = onSend
            self.minimumHeight = minimumHeight
            self.maximumHeight = maximumHeight
            parent = ComposerInputHost(
                text: text,
                height: height,
                onSend: onSend,
                minimumHeight: minimumHeight,
                maximumHeight: maximumHeight,
                textHex: "#F4F4F5",
                accentHex: "#2563EB"
            )
        }

        func attach(textView: NSTextView, container: ComposerInputContainer) {
            self.textView = textView
            self.container = container
        }

        func shouldSkipSync(for textView: NSTextView) -> Bool {
            textView.window?.firstResponder === textView || textView.hasMarkedText()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
            updateHeight(for: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) { return false }
            onSend()
            return true
        }

        private func updateHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2
            let natural = max(used + 8, minimumHeight)
            let clamped = min(natural, maximumHeight)
            height = clamped
            container?.layoutTextView(proposedHeight: clamped)
            container?.scrollView.hasVerticalScroller = natural > maximumHeight
        }
    }
}

final class ComposerInputContainer: NSView {
    let scrollView = NSScrollView()
    let textView: NSTextView
    private let minimumHeight: CGFloat

    init(minimumHeight: CGFloat) {
        self.minimumHeight = minimumHeight
        textView = NSTextView()
        super.init(frame: .zero)
        wantsLayer = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: LayoutMetrics.composerFontSize)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: minimumHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 2, height: 6)
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView.documentView = textView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: max(minimumHeight, bounds.height))
    }

    override func layout() {
        super.layout()
        layoutTextView(proposedHeight: bounds.height)
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        window?.makeFirstResponder(textView)
        super.mouseDown(with: event)
    }

    func layoutTextView(proposedHeight: CGFloat) {
        let width = max(bounds.width, 1)
        let resolvedHeight = max(proposedHeight, minimumHeight)
        if abs(textView.frame.width - width) > 0.5 || abs(textView.frame.height - resolvedHeight) > 0.5 {
            textView.frame = NSRect(x: 0, y: 0, width: width, height: resolvedHeight)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

private extension NSColor {
    static func fromHex(_ hex: String) -> NSColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (a, r, g, b) = (255, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
        case 8:
            (a, r, g, b) = ((value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
        default:
            (a, r, g, b) = (255, 244, 244, 245)
        }
        return NSColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
