import AppKit
import SwiftUI

/// Configures the hosting `NSWindow` so only explicit drag handles move the window.
/// With `.hiddenTitleBar`, macOS otherwise treats the full client area as draggable and
/// can swallow clicks / keyboard focus for text inputs.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.isMovableByWindowBackground = false
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
    }
}

/// Drag handle limited to the custom title bar region.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowDragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
