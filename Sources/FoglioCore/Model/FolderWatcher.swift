import Foundation

/// Fires when a directory's contents change.
///
/// The point is that re-exporting from Google should be enough on its own: drop
/// a new export into the watched folder and the calendar updates, with no
/// "Reload" click. Since a manual export is the only route this user's admin
/// leaves open, removing every step that isn't the export itself matters.
@MainActor
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1

    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit {
        source?.cancel()
    }

    func watch(_ url: URL) {
        stop()

        let directory = ICSImporter.isDirectory(url) ? url : url.deletingLastPathComponent()
        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            // A download lands as a .part/.crdownload first, so give the write
            // a moment to settle before reading.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { self?.onChange() }
            }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }
}
