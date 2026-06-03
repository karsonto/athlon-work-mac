import Foundation

/// Batches high-frequency streaming UI updates (~30fps) to reduce SwiftUI diff work.
final class StreamingUiCoalescer {
    private let intervalSeconds: TimeInterval
    private let flushHandler: () -> Void
    private var scheduledWork: DispatchWorkItem?

    init(intervalMilliseconds: Int = 32, flushHandler: @escaping () -> Void) {
        self.intervalSeconds = TimeInterval(intervalMilliseconds) / 1000
        self.flushHandler = flushHandler
    }

    func scheduleFlush() {
        scheduledWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scheduledWork = nil
            self.flushHandler()
        }
        scheduledWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + intervalSeconds, execute: work)
    }

    func flushNow() {
        scheduledWork?.cancel()
        scheduledWork = nil
        if Thread.isMainThread {
            flushHandler()
        } else {
            DispatchQueue.main.sync(execute: flushHandler)
        }
    }

    func cancel() {
        scheduledWork?.cancel()
        scheduledWork = nil
    }
}
