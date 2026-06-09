import Foundation
import AppKit

struct ResolvedApp: Sendable {
    let pid: pid_t
    let path: String
    let runningApp: NSRunningApplication?
    let bundleID: String?
}

actor ProcessResolver {
    func resolve(tuple: SocketTuple) async throws -> ResolvedApp? {
        var pids = Array(repeating: pid_t(0), count: 4096)
        let bytes = sim_proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return nil }

        let count = Int(bytes) / MemoryLayout<pid_t>.size
        for pid in pids.prefix(count) where pid > 0 {
            if let match = match(pid: pid, tuple: tuple) {
                return match
            }
        }
        return nil
    }

    private func match(pid: pid_t, tuple: SocketTuple) -> ResolvedApp? {
        var fdBuf = Array(repeating: proc_fdinfo(), count: 256)
        let fdBytes = sim_proc_pidinfo(
            pid,
            PROC_PIDLISTFDS,
            0,
            &fdBuf,
            Int32(fdBuf.count * MemoryLayout<proc_fdinfo>.size)
        )
        guard fdBytes > 0 else { return nil }

        let fdCount = Int(fdBytes) / MemoryLayout<proc_fdinfo>.size
        for fd in fdBuf.prefix(fdCount) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var sfi = socket_fdinfo()
            let ok = sim_proc_pidfdinfo(
                pid,
                fd.proc_fd,
                PROC_PIDFDSOCKETINFO,
                &sfi,
                Int32(MemoryLayout<socket_fdinfo>.size)
            )
            guard ok == MemoryLayout<socket_fdinfo>.size else { continue }

            // For IPv4/IPv6 TCP sockets, compare the tuple
            guard sfi.psi.soi_kind == SOCKINFO_TCP else { continue }

            let ini = sfi.psi.soi_proto.pri_tcp.tcpsi_ini

            let localPort = sim_ntohs(UInt16(truncatingIfNeeded: ini.insi_lport))
            let remotePort = sim_ntohs(UInt16(truncatingIfNeeded: ini.insi_fport))

            if localPort == tuple.remotePort && remotePort == tuple.localPort {
                var pathBuf = Array<CChar>(repeating: 0, count: Int(sim_proc_pidpathinfo_maxsize()))
                let len = sim_proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
                let pathBytes = pathBuf
                    .prefix { $0 != 0 }
                    .map { UInt8(bitPattern: $0) }
                let path = len > 0 ? String(decoding: pathBytes, as: UTF8.self) : ""

                let app = NSRunningApplication(processIdentifier: pid)
                return ResolvedApp(
                    pid: pid,
                    path: path,
                    runningApp: app,
                    bundleID: app?.bundleIdentifier
                )
            }
        }
        return nil
    }
}
