import AppKit
import Foundation

/// The process that owns a given TCP connection, resolved from a socket tuple.
struct ResolvedApp: Sendable {
    let path: String
    let runningApp: NSRunningApplication?
    let bundleID: String?
}

/// Attributes an incoming proxy connection to the local process that opened it.
///
/// When the proxy accepts a connection it only knows the socket tuple
/// (local/remote address and port). This actor walks every process on the
/// system via the libproc APIs, inspects each process's open socket file
/// descriptors, and looks for a TCP socket whose endpoints mirror that tuple.
actor ProcessResolver {
    func resolve(tuple: SocketTuple) async throws -> ResolvedApp? {
        // Fetch the PIDs of all running processes.
        // sim_proc_listallpids returns the number of bytes
        // actually written, from which we derive the real PID count.
        var pids = Array(repeating: pid_t(0), count: 4096)
        let bytes = sim_proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return nil }

        // Scan each process until one owns a socket matching the tuple.
        let count = Int(bytes) / MemoryLayout<pid_t>.size
        for pid in pids.prefix(count) where pid > 0 {
            if let match = match(pid: pid, tuple: tuple) {
                return match
            }
        }
        return nil
    }

    /// Checks whether `pid` owns a TCP socket that is the peer side of `tuple`.
    private func match(pid: pid_t, tuple: SocketTuple) -> ResolvedApp? {
        // List the process's open file descriptors of any type.
        var fdBuf = Array(repeating: proc_fdinfo(), count: 256)
        let fdBytes = sim_proc_pidinfo(
            pid,
            PROC_PIDLISTFDS,
            0,
            &fdBuf,
            Int32(fdBuf.count * MemoryLayout<proc_fdinfo>.size)
        )
        guard fdBytes > 0 else { return nil }

        // Only socket descriptors are of interest.
        let fdCount = Int(fdBytes) / MemoryLayout<proc_fdinfo>.size
        for fd in fdBuf.prefix(fdCount) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            // Ask the kernel for detailed socket info for this descriptor.
            var sfi = socket_fdinfo()
            let ok = sim_proc_pidfdinfo(
                pid,
                fd.proc_fd,
                PROC_PIDFDSOCKETINFO,
                &sfi,
                Int32(MemoryLayout<socket_fdinfo>.size)
            )
            guard ok == MemoryLayout<socket_fdinfo>.size else { continue }

            // Skip anything that isn't a TCP socket
            guard sfi.psi.soi_kind == SOCKINFO_TCP else { continue }

            let ini = sfi.psi.soi_proto.pri_tcp.tcpsi_ini

            // Ports are stored in network byte order; convert to host order.
            let localPort = sim_ntohs(UInt16(truncatingIfNeeded: ini.insi_lport))
            let remotePort = sim_ntohs(UInt16(truncatingIfNeeded: ini.insi_fport))

            // The tuple describes the connection from the proxy's point of
            // view, so the client's socket has the ports swapped: its local
            // port is the proxy's remote port and vice versa
            if localPort == tuple.remotePort && remotePort == tuple.localPort {
                // Resolve the executable path for the matching process.
                var pathBuf = [CChar](repeating: 0, count: Int(sim_proc_pidpathinfo_maxsize()))
                let len = sim_proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
                // The buffer is NUL-terminated; keep only the bytes before
                // the terminator and decode them as UTF-8.
                let pathBytes = pathBuf
                    .prefix { $0 != 0 }
                    .map { UInt8(bitPattern: $0) }
                let path = len > 0 ? String(decoding: pathBytes, as: UTF8.self) : ""

                // NSRunningApplication is nil for non-app processes
                let app = NSRunningApplication(processIdentifier: pid)
                let bundleID = app?.bundleIdentifier ?? Self.bundleIdentifier(forExecutablePath: path)

                return ResolvedApp(
                    path: path,
                    runningApp: app,
                    bundleID: bundleID
                )
            }
        }
        return nil
    }

    private static func bundleIdentifier(forExecutablePath path: String) -> String? {
        guard !path.isEmpty else { return nil }

        var url = URL(fileURLWithPath: path)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if url.pathExtension == "app" {
                return Bundle(url: url)?.bundleIdentifier
            }
        }
        return nil
    }
}
