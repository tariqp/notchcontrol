import Foundation

/// Unix-socket server that receives one JSON event per connection from
/// `notchcontrol-bridge` and optionally sends back one JSON line as the reply.
final class BridgeServer {
    static let socketPath = AppPaths.supportDir.appendingPathComponent("bridge.sock").path

    typealias Handler = (_ event: [String: Any], _ respond: @escaping (String?) -> Void) -> Void
    var handler: Handler?

    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "notchcontrol.bridge", attributes: .concurrent)

    enum BridgeError: Error { case socket, bind, listen, pathTooLong }

    func start() throws {
        unlink(Self.socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError.socket }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Self.socketPath.utf8CString
        guard path.count <= MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); throw BridgeError.pathTooLong }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: path.count) { dst in
                for (i, c) in path.enumerated() { dst[i] = c }
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard rc == 0 else { close(fd); throw BridgeError.bind }
        guard listen(fd, 16) == 0 else { close(fd); throw BridgeError.listen }
        chmod(Self.socketPath, 0o600)
        listenFD = fd

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(Self.socketPath)
    }

    private func acceptOne() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        var one: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        queue.async { [weak self] in self?.serve(client) }
    }

    private func serve(_ fd: Int32) {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
            if buf[..<n].contains(0x0A) || data.count > 4_000_000 { break }
        }
        guard let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            close(fd)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let handler = self.handler else { close(fd); return }
            handler(event) { reply in
                self.queue.async {
                    if let reply, var out = reply.data(using: .utf8) {
                        out.append(0x0A)
                        out.withUnsafeBytes { b in
                            var off = 0
                            while off < b.count {
                                let n = write(fd, b.baseAddress! + off, b.count - off)
                                if n <= 0 { break }
                                off += n
                            }
                        }
                    }
                    close(fd)
                }
            }
        }
    }
}
