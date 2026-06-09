// AthlonAgent/Services/WorkspaceFileWatcherService.swift
import Foundation

/// Monitors workspace file changes using DispatchSource (macOS equivalent of FileSystemWatcher).
/// Fires the `onFileChanged` callback on the main actor when a watched path is modified.
@MainActor
final class WorkspaceFileWatcherService {
    private var source: DispatchSourceFileSystemObject?
    private var watchedPath: String?
    private var fileDescriptor: Int32 = -1
    private let onFileChanged: (String) -> Void

    init(onFileChanged: @escaping (String) -> Void) {
        self.onFileChanged = onFileChanged
    }

    /// Watch a directory for write events (e.g. workspace root).
    /// When any file inside the directory is written, `onFileChanged` fires with the watched path.
    /// The handler then checks whether any open editor tab matches the changed file.
    func watchDirectory(path: String) {
        stop()

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // DispatchSource for directories does not provide the exact file path.
            // Pass the watched directory; the receiver (FileEditorViewModel.handleExternalChange)
            // will check if any open tab matches by re-scanning the directory or relying on
            // the VM's existing path matching.
            DispatchQueue.main.async { [weak self] in
                self?.onFileChanged(path)
            }
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        source.resume()
        self.source = source
        self.watchedPath = path
    }

    /// Watch a single file for write, rename, or delete events.
    func watchFile(path: String) {
        stop()

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onFileChanged(path)
            }
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        source.resume()
        self.source = source
        self.watchedPath = path
    }

    /// Stop watching and release resources.
    func stop() {
        source?.cancel()
        source = nil
        watchedPath = nil
        // fileDescriptor is closed inside the cancel handler
        fileDescriptor = -1
    }

    deinit {
        // Ensure the source is cancelled and fd closed
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}
