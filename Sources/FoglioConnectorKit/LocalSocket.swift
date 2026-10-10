import Foundation
import Darwin

/// IPC only: no TCP listener, browser endpoint, or independent library writer.
public enum ConnectorSocket {
    public static let maximumMessageBytes = 4 * 1024 * 1024
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Foglio/agent.sock")
    }
    private static func address(_ url: URL) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(url.path.utf8) + [0]
        guard !bytes.dropLast().contains(0), bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw ConnectorError("socket_path", "The connector socket path is too long.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }
    static func endpoint(_ url: URL, _ action: (UnsafePointer<sockaddr>, socklen_t) -> Int32) throws -> Int32 {
        var value = try address(url)
        return withUnsafePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { action($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
    static func configure(_ fd: Int32) {
        var enabled: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled)))
        var timeout = timeval(tv_sec: 45, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    static func read(_ fd: Int32) throws -> JSON {
        var result = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ConnectorError("connection_closed", "Foglio closed the connector or the request timed out.") }
            result.append(contentsOf: buffer.prefix(count))
            guard result.count <= maximumMessageBytes else { throw ConnectorError("message_too_large", "Connector messages are limited to 4 MiB.") }
            if let newline = result.firstIndex(of: 10) { return try JSON.decode(result.prefix(upTo: newline)) }
        }
    }
    static func write(_ value: JSON, _ fd: Int32) throws {
        var data = try value.data()
        guard data.count < maximumMessageBytes else { throw ConnectorError("message_too_large", "This response exceeds the 4 MiB connector limit. Use smaller list pages.") }
        data.append(10)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ConnectorError("connection_closed", "Could not send the connector message.") }
                offset += count
            }
        }
    }
    public static func request(_ value: JSON, at url: URL = defaultURL) throws -> JSON {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ConnectorError("socket_failed", "Could not open a local socket.") }
        defer { Darwin.close(fd) }
        configure(fd)
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let connected = try endpoint(url) { Darwin.connect(fd, $0, $1) }
        if connected != 0 {
            guard errno == EINPROGRESS || errno == EAGAIN else {
                throw ConnectorError("app_unavailable", "Open the updated Foglio app and enable Settings → Agent connections.")
            }
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            var socketError: Int32 = 0, length = socklen_t(MemoryLayout<Int32>.size)
            guard poll(&descriptor, 1, 5000) > 0,
                  getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0, socketError == 0 else {
                throw ConnectorError("app_unavailable", "Foglio's connector is unavailable or busy. Check Settings → Agent connections.")
            }
        }
        _ = fcntl(fd, F_SETFL, flags)
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw ConnectorError("wrong_user", "Connector belongs to another macOS user.") }
        try write(value, fd)
        return try read(fd)
    }
}

public final class LocalConnectorServer {
    public typealias Handler = (JSON, @escaping (JSON) -> Void) -> Void
    private let url: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "foglio.connector.accept")
    private let workers = DispatchQueue(label: "foglio.connector.requests", attributes: .concurrent)
    private var source: DispatchSourceRead?
    private let lock = NSLock()
    private var clients: Set<Int32> = []
    private var stopped = false
    private var inode: ino_t?

    public init(url: URL = ConnectorSocket.defaultURL, handler: @escaping Handler) { self.url = url; self.handler = handler }
    public func start() throws {
        guard source == nil else { return }
        guard !stopped else { throw ConnectorError("stopped", "Create a new connector server to restart it.") }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var attributes = stat()
        guard lstat(directory.path, &attributes) == 0, (attributes.st_mode & S_IFMT) == S_IFDIR, attributes.st_uid == getuid() else {
            throw ConnectorError("unsafe_directory", "Connector directory must belong to you and must not be a symbolic link.")
        }
        guard chmod(directory.path, 0o700) == 0 else { throw ConnectorError("unsafe_directory", "Could not restrict connector directory permissions.") }
        if lstat(url.path, &attributes) == 0 {
            guard (attributes.st_mode & S_IFMT) == S_IFSOCK, attributes.st_uid == getuid() else {
                throw ConnectorError("unsafe_socket", "Refusing to replace a file or link at the connector socket path.")
            }
            let previousInode = attributes.st_ino
            let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard probe >= 0 else { throw ConnectorError("socket_failed", "Could not check the existing socket.") }
            _ = fcntl(probe, F_SETFL, fcntl(probe, F_GETFL) | O_NONBLOCK)
            let status = try ConnectorSocket.endpoint(url) { Darwin.connect(probe, $0, $1) }
            let error = errno
            Darwin.close(probe)
            guard status != 0, error == ECONNREFUSED || error == ENOENT else {
                throw ConnectorError("already_running", "Another Foglio connector is already running.")
            }
            guard lstat(url.path, &attributes) == 0, attributes.st_ino == previousInode, unlink(url.path) == 0 else {
                throw ConnectorError("socket_failed", "The previous connector socket changed. Try again.")
            }
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ConnectorError("socket_failed", "Could not create the connector socket.") }
        var installed = false
        defer { if !installed { Darwin.close(fd) } }
        guard try ConnectorSocket.endpoint(url, { Darwin.bind(fd, $0, $1) }) == 0 else {
            throw ConnectorError("socket_failed", "Could not bind the connector socket.")
        }
        guard chmod(url.path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
            unlink(url.path)
            throw ConnectorError("socket_failed", "Could not secure or start the connector socket.")
        }
        if lstat(url.path, &attributes) == 0 { inode = attributes.st_ino }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let listener = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        listener.setEventHandler { [weak self] in self?.acceptConnections(fd) }
        listener.setCancelHandler { Darwin.close(fd) }
        source = listener; installed = true; listener.resume()
    }
    private func acceptConnections(_ listener: Int32) {
        while true {
            let fd = Darwin.accept(listener, nil, nil)
            if fd < 0 { return }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { Darwin.close(fd); continue }
            lock.lock()
            let admitted = !stopped && clients.count < 8
            if admitted { clients.insert(fd) }
            lock.unlock()
            guard admitted else { Darwin.close(fd); continue }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
            ConnectorSocket.configure(fd)
            workers.async { [self] in
                do {
                    let request = try ConnectorSocket.read(fd)
                    handler(request) { [self] result in workers.async { [self] in finish(fd, result: result) } }
                } catch { finish(fd, result: ["ok": false, "error": ConnectorError("invalid_request", error.localizedDescription).json]) }
            }
        }
    }
    private func finish(_ fd: Int32, result: JSON) {
        // stop() shuts down reads/writes but lets their owners close descriptors,
        // so a recycled descriptor cannot be closed by a late response.
        do { try ConnectorSocket.write(result, fd) }
        catch { try? ConnectorSocket.write(["ok": false, "error": ConnectorError("response_failed", error.localizedDescription).json], fd) }
        lock.lock(); clients.remove(fd); Darwin.close(fd); lock.unlock()
    }
    public func stop() {
        lock.lock(); stopped = true
        for fd in clients { Darwin.shutdown(fd, SHUT_RDWR) }
        lock.unlock()
        source?.cancel(); source = nil
        var attributes = stat()
        if let inode, lstat(url.path, &attributes) == 0, attributes.st_ino == inode,
           (attributes.st_mode & S_IFMT) == S_IFSOCK { unlink(url.path) }
        inode = nil
    }
    deinit { stop() }
}
