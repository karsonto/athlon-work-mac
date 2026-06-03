import Foundation

/// Tracks shell processes started by `execute_command` (aligned with WPF `ExecuteCommandProcessRegistry`).
final class ExecuteCommandProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [Int32: Process] = [:]

    func register(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        processes[process.processIdentifier] = process
    }

    func unregister(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        processes.removeValue(forKey: process.processIdentifier)
    }

    func killAll() {
        lock.lock()
        let snapshot = Array(processes.values)
        processes.removeAll()
        lock.unlock()

        for process in snapshot {
            ProcessKillHelper.killProcessTree(process)
        }
    }
}

enum ProcessKillHelper {
    static func killProcessTree(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            if process.isRunning {
                process.interrupt()
            }
        }
    }
}
