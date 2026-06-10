import SwiftUI

// MARK: - macOS 12 Compatibility Wrappers

extension View {
    /// macOS 12-compatible `onChange` wrapper.
    /// - On macOS 14+, uses the two-parameter closure `(oldValue, newValue)`.
    /// - On macOS 12-13, uses the single-parameter closure `(newValue)`.
    @ViewBuilder
    func onValueChange<V: Equatable>(
        of value: V,
        perform action: @escaping (_ newValue: V) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value, perform: action)
        }
    }

    /// Hides scroll view content background on macOS 13+; no-op on macOS 12.
    @ViewBuilder
    func hideScrollContentBackgroundIfAvailable() -> some View {
        if #available(macOS 13.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
