import Foundation
import os.lock

/// A simple os_unfair_lock wrapper that is safe to use from async Swift 6 contexts.
final class Lock: @unchecked Sendable {
    private var _lock = os_unfair_lock()
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return try body()
    }
}

struct SessionTurnRequest {
    let sessionId: String
    var session: AgentSession
    let userInput: String
    let imageAttachments: [ImageAttachment]
    let ui: SessionTurnUiController
    let isAutoContinue: Bool
}

struct SessionTurnCompletedEvent {
    let sessionId: String
    let session: AgentSession
    let cancelled: Bool
    let timedOut: Bool
    let isAutoContinue: Bool
    let error: Error?
}

/// Runs agent turns with global concurrency cap and per-session exclusivity.
final class SessionTurnHost {
    static let maxConcurrentTurns = 3

    typealias TurnExecutor = (
        SessionTurnRequest,
        @escaping (String) -> Void,
        @escaping (AgentToolCall) -> Void,
        @escaping (String) -> Void,
        @escaping (Result<String, Error>) -> Void
    ) -> Void

    private let settingsProvider: () -> AgentTurnSettings
    private let executor: TurnExecutor
    private let queue = SessionTurnQueue()
    private let startGate = Lock()
    private var runners: [String: SessionTurnRunner] = [:]

    var onTurnCompleted: ((SessionTurnCompletedEvent) -> Void)?
    var onTurnStateChanged: ((String) -> Void)?
    /// Reconcile cancelled/timed-out/error turns before UI finalization (aligned with WPF `SessionTurnHost.Runner`).
    var onReconcileTurn: (
        @MainActor (
            SessionTurnRequest,
            AgentSession,
            Bool,
            Bool,
            String?
        ) -> (session: AgentSession, persistedMessages: [ChatMessage])
    )?

    init(settingsProvider: @escaping () -> AgentTurnSettings, executor: @escaping TurnExecutor) {
        self.settingsProvider = settingsProvider
        self.executor = executor
    }

    func tryStart(_ request: SessionTurnRequest) -> String? {
        startGate.withLock {
            if runners[request.sessionId] != nil {
                return "当前对话正在生成，请等待完成或先停止。"
            }
            if runners.count >= Self.maxConcurrentTurns {
                return "已有 3 个对话在生成，请等待或停止其中一个。"
            }

            let timeout = settingsProvider().resolveTurnTimeout()
            let runner = SessionTurnRunner(host: self, request: request, timeout: timeout)
            runners[request.sessionId] = runner
            onTurnStateChanged?(request.sessionId)
            runner.start()
            return nil
        }
    }

    func isRunning(_ sessionId: String) -> Bool {
        startGate.withLock { runners[sessionId] != nil }
    }

    func runningSessionIds() -> [String] {
        startGate.withLock { Array(runners.keys) }
    }

    func enqueue(_ payload: QueuedTurnPayload) {
        queue.enqueue(payload)
        onTurnStateChanged?(payload.sessionId)
    }

    func tryDequeue(sessionId: String) -> QueuedTurnPayload? {
        queue.dequeue(sessionId: sessionId)
    }

    func requeueFront(_ payload: QueuedTurnPayload) {
        queue.requeueFront(payload)
    }

    func removeQueued(sessionId: String, queueId: String) -> Bool {
        queue.remove(sessionId: sessionId, queueId: queueId)
    }

    func clearQueue(sessionId: String) {
        queue.clear(sessionId: sessionId)
    }

    func queueCount(sessionId: String) -> Int {
        queue.count(sessionId: sessionId)
    }

    func queuedPayloads(sessionId: String) -> [QueuedTurnPayload] {
        queue.snapshot(sessionId: sessionId)
    }

    func hasQueuedTurns(sessionId: String) -> Bool {
        queue.hasQueuedTurns(sessionId: sessionId)
    }

    func cancel(sessionId: String) {
        let runner = startGate.withLock { runners[sessionId] }
        runner?.cancel()
    }

    /// Removes the runner immediately so a new message can start without queuing (WPF `Stop` + fast unwind).
    func abortTurn(sessionId: String) -> SessionTurnRequest? {
        let runner = startGate.withLock { runners.removeValue(forKey: sessionId) }
        guard let runner else { return nil }
        runner.cancel()
        onTurnStateChanged?(sessionId)
        return runner.turnRequest
    }

    /// Returns false when the runner was already removed (e.g. user stop via `abortTurn`).
    private func consumeRunnerFinish(for runner: SessionTurnRunner) -> Bool {
        startGate.withLock { runners.removeValue(forKey: runner.sessionId) != nil }
    }

    private func notifyTurnCompleted(
        runner: SessionTurnRunner,
        session: AgentSession,
        cancelled: Bool,
        timedOut: Bool,
        error: Error?
    ) {
        onTurnStateChanged?(runner.sessionId)
        onTurnCompleted?(
            SessionTurnCompletedEvent(
                sessionId: runner.sessionId,
                session: session,
                cancelled: cancelled,
                timedOut: timedOut,
                isAutoContinue: runner.isAutoContinue,
                error: error
            )
        )
    }

    /// Stops work and drops per-session state when a conversation is deleted.
    func dropSession(_ sessionId: String) {
        cancel(sessionId: sessionId)
        clearQueue(sessionId: sessionId)
        startGate.withLock { runners.removeValue(forKey: sessionId) }
        onTurnStateChanged?(sessionId)
    }

    func cancelAll() {
        let all = startGate.withLock { Array(runners.values) }
        all.forEach { $0.cancel() }
    }

    /// Waits for active runners to finish after cancel (aligned with WPF `ShutdownAsync`).
    func shutdownAsync(timeout: TimeInterval = 15) async {
        cancelAll()
        clearAllQueues()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let active = startGate.withLock { runners.isEmpty }
            if active { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func hasActiveWork() -> Bool {
        let running = startGate.withLock { !runners.isEmpty }
        return running || queue.hasAnyQueuedTurns()
    }

    func clearAllQueues() {
        queue.clearAll()
    }

    private final class SessionTurnRunner {
        private weak var host: SessionTurnHost?
        private var request: SessionTurnRequest
        private let timeout: TimeInterval?
        private var cancelled = false

        var sessionId: String { request.sessionId }
        var isAutoContinue: Bool { request.isAutoContinue }
        var turnRequest: SessionTurnRequest { request }

        init(host: SessionTurnHost, request: SessionTurnRequest, timeout: TimeInterval?) {
            self.host = host
            self.request = request
            self.timeout = timeout
        }

        func start() {
            var timeoutWork: DispatchWorkItem?
            if let timeout {
                timeoutWork = DispatchWorkItem { [weak self] in
                    self?.cancel(timedOut: true)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork!)
            }

            Task { @MainActor [weak self] in
                guard let self, let host = self.host else { return }
                self.request.ui.resetForTurn()
                host.executor(
                    self.request,
                    { chunk in self.request.ui.appendStreamingText(chunk) },
                    { toolCall in self.request.ui.appendToolCall(toolCall) },
                    { reasoning in self.request.ui.appendReasoning(reasoning) }
                ) { result in
                    timeoutWork?.cancel()
                    guard host.consumeRunnerFinish(for: self) else { return }

                    let timedOut = self.cancelled && self.timeout != nil
                    let errorMessage: String? = {
                        if self.cancelled, !timedOut { return nil }
                        if case .failure(let error) = result {
                            if SessionTurnHost.isCancellationError(error) { return nil }
                            return error.localizedDescription
                        }
                        return nil
                    }()

                    var session = self.request.session
                    var reconciled: [ChatMessage] = []
                    if self.cancelled || timedOut || errorMessage != nil,
                       let reconcile = host.onReconcileTurn {
                        let outcome = reconcile(
                            self.request,
                            session,
                            self.cancelled,
                            timedOut,
                            errorMessage
                        )
                        session = outcome.session
                        reconciled = outcome.persistedMessages
                        self.request.session = session
                    }

                    switch result {
                    case .success(let text):
                        self.request.ui.finalizeTurn(
                            fullText: text,
                            cancelled: self.cancelled,
                            timedOut: timedOut,
                            errorMessage: nil,
                            reconciledMessages: reconciled
                        )
                        host.notifyTurnCompleted(
                            runner: self,
                            session: session,
                            cancelled: self.cancelled,
                            timedOut: timedOut,
                            error: nil
                        )
                    case .failure(let error):
                        self.request.ui.finalizeTurn(
                            fullText: "",
                            cancelled: self.cancelled,
                            timedOut: timedOut,
                            errorMessage: error.localizedDescription,
                            reconciledMessages: reconciled
                        )
                        host.notifyTurnCompleted(
                            runner: self,
                            session: session,
                            cancelled: self.cancelled,
                            timedOut: timedOut,
                            error: error
                        )
                    }
                }
            }
        }

        func cancel(timedOut: Bool = false) {
            cancelled = true
            _ = timedOut
        }
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        return false
    }
}
