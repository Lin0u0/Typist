//
//  DirectoryMonitor.swift
//  Typist
//

import Foundation

/// Watches a directory for filesystem changes (files/folders added or removed)
/// using a DispatchSource. Callbacks are delivered on the main queue.
@MainActor
final class DirectoryMonitor {
    private var source: DispatchSourceFileSystemObject?
    var onChange: (() -> Void)?

    func start(url: URL) {
        stop()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.onChange?() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { source?.cancel() }
}
