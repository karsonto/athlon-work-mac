import Foundation

/// CRUD + timer loop for scheduled tasks persisted in AppSettings.schedule.
@MainActor
@Observable
final class ScheduleStore {
    private let storage: FileStorageService
    private let runtimeProvider: () -> AgentRuntime?
    private var pollTask: Task<Void, Never>?
    private var keepAwakeActivity: NSObjectProtocol?

    var settings: ScheduleSettings
    var statusMessage: String = ""

    init(
        storage: FileStorageService = FileStorageService(),
        runtimeProvider: @escaping () -> AgentRuntime? = { nil }
    ) {
        self.storage = storage
        self.runtimeProvider = runtimeProvider
        let app = (try? storage.loadSettings()) ?? AppSettings()
        self.settings = app.schedule
    }

    func start() {
        stop()
        applyKeepAwake()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        endKeepAwake()
    }

    func reload() {
        let app = (try? storage.loadSettings()) ?? AppSettings()
        settings = app.schedule
        applyKeepAwake()
    }

    func persist() {
        do {
            var app = try storage.loadSettings()
            app.schedule = settings
            try storage.saveSettings(app)
            applyKeepAwake()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addTask() {
        var task = ScheduledTask()
        let now = ISO8601DateFormatter.athlon.string(from: Date())
        task.title = "New task"
        task.createdAt = now
        task.updatedAt = now
        task.nextRunAt = Self.computeNextRun(for: task, after: Date())
        settings.tasks.insert(task, at: 0)
        persist()
    }

    func updateTask(_ task: ScheduledTask) {
        guard let idx = settings.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var copy = task
        copy.updatedAt = ISO8601DateFormatter.athlon.string(from: Date())
        copy.nextRunAt = Self.computeNextRun(for: copy, after: Date())
        settings.tasks[idx] = copy
        persist()
    }

    func deleteTask(id: String) {
        settings.tasks.removeAll { $0.id == id }
        persist()
    }

    func runNow(_ task: ScheduledTask) {
        Task {
            await fire(task)
        }
    }

    // MARK: - Scheduler

    private func tick() async {
        guard settings.enabled else { return }
        let now = Date()
        for task in settings.tasks where task.enabled {
            guard let next = Self.parseDate(task.nextRunAt), next <= now else { continue }
            await fire(task)
        }
    }

    private func fire(_ task: ScheduledTask) async {
        var updated = task
        let started = Date()
        updated.lastRunAt = ISO8601DateFormatter.athlon.string(from: started)
        updated.lastStatus = "running"
        updated.lastMessage = ""
        replace(updated)

        let promptPrefix = settings.promptPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = task.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullPrompt = [promptPrefix, body].filter { !$0.isEmpty }.joined(separator: "\n\n")

        do {
            guard let runtime = runtimeProvider() else {
                throw AgentRuntimeError.turnFailed("AgentRuntime not available")
            }
            let session = AgentSession(title: "Schedule: \(task.title)")
            try storage.saveSession(session)
            let workspace = task.workspaceRoot.isEmpty
                ? (settings.defaultWorkspaceRoot.isEmpty ? nil : settings.defaultWorkspaceRoot)
                : task.workspaceRoot
            _ = try await runtime.runTurn(
                sessionId: session.id,
                userText: fullPrompt.isEmpty ? "(empty scheduled prompt)" : fullPrompt,
                workspaceRoot: workspace
            )
            updated.lastStatus = "ok"
            updated.lastMessage = "completed"
            updated.lastThreadId = session.id
        } catch {
            updated.lastStatus = "error"
            updated.lastMessage = error.localizedDescription
        }

        updated.lastRunEndedAt = ISO8601DateFormatter.athlon.string(from: Date())
        if task.kind.lowercased() == "once" || task.kind.lowercased() == "at" {
            updated.enabled = false
            updated.nextRunAt = ""
        } else {
            updated.nextRunAt = Self.computeNextRun(for: updated, after: Date())
        }
        replace(updated)
        persist()
    }

    private func replace(_ task: ScheduledTask) {
        if let idx = settings.tasks.firstIndex(where: { $0.id == task.id }) {
            settings.tasks[idx] = task
        }
    }

    private func applyKeepAwake() {
        endKeepAwake()
        guard settings.enabled, settings.keepAwake else { return }
        keepAwakeActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Athlon Agent schedule KeepAwake"
        )
    }

    private func endKeepAwake() {
        if let keepAwakeActivity {
            ProcessInfo.processInfo.endActivity(keepAwakeActivity)
            self.keepAwakeActivity = nil
        }
    }

    // MARK: - Next run helpers

    static func computeNextRun(for task: ScheduledTask, after date: Date) -> String {
        let calendar = Calendar.current
        let kind = task.kind.lowercased()
        let next: Date
        switch kind {
        case "interval", "every":
            let minutes = max(1, task.everyMinutes)
            next = date.addingTimeInterval(TimeInterval(minutes * 60))
        case "once", "at":
            if let at = parseTimeOfDay(task.atTime.isEmpty ? task.timeOfDay : task.atTime, on: date, calendar: calendar),
               at > date {
                next = at
            } else if let at = parseTimeOfDay(task.atTime.isEmpty ? task.timeOfDay : task.atTime, on: date, calendar: calendar) {
                next = calendar.date(byAdding: .day, value: 1, to: at) ?? date.addingTimeInterval(86400)
            } else {
                next = date.addingTimeInterval(3600)
            }
        default: // daily
            if let tod = parseTimeOfDay(task.timeOfDay, on: date, calendar: calendar) {
                next = tod > date ? tod : (calendar.date(byAdding: .day, value: 1, to: tod) ?? tod.addingTimeInterval(86400))
            } else {
                next = date.addingTimeInterval(86400)
            }
        }
        return ISO8601DateFormatter.athlon.string(from: next)
    }

    static func parseDate(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        return ISO8601DateFormatter.athlon.date(from: text)
            ?? ISO8601DateFormatter.athlonFractional.date(from: text)
    }

    private static func parseTimeOfDay(_ text: String, on date: Date, calendar: Calendar) -> Date? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = parts[0]
        comps.minute = parts[1]
        comps.second = parts.count > 2 ? parts[2] : 0
        return calendar.date(from: comps)
    }
}
