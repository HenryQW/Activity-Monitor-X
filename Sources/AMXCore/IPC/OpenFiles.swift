import Foundation

/// An open file or network socket of a process, as the inspector's Files pill lists it.
public enum OpenItem: Codable, Sendable, Hashable {
    case file(path: String)
    /// `proto` is TCP, UDP or Unix; an address is "host:port", "*" for none; `state` is a TCP state, else empty.
    case socket(proto: String, local: String, remote: String, state: String)
}

/// One process's open items: at most `OpenFiles.limit`, and the count of the others.
public struct OpenItems: Codable, Sendable, Equatable {
    public let pid: Int32
    public let items: [OpenItem]
    public let more: Int
}

/// Reads open files and sockets with libproc. `amxd` reads them, as root, for the caller's own processes only.
public enum OpenFiles {
    /// Items per process and processes per request, so a reply stays small.
    public static let limit = 500, maxProcesses = 32

    /// The socket facts `item` needs, from `proc_pidfdinfo`.
    struct Socket {
        var family: Int32
        var type: Int32
        /// 4 bytes for IPv4, 16 for IPv6, in network order.
        var local: [UInt8] = [], localPort: UInt16 = 0
        var remote: [UInt8] = [], remotePort: UInt16 = 0
        var tcpState: Int32?
        var unixPath = ""
    }

    private static let tcpStates = ["Closed", "Listen", "SYN Sent", "SYN Received", "Established", "Close Wait",
                                    "FIN Wait 1", "Closing", "Last ACK", "FIN Wait 2", "Time Wait"]

    /// Nil for a socket the list does not show: an unnamed Unix socket, or another family.
    static func item(_ s: Socket) -> OpenItem? {
        switch s.family {
        case AF_INET, AF_INET6:
            let state = s.tcpState.map { tcpStates.indices.contains(Int($0)) ? tcpStates[Int($0)] : "" } ?? ""
            return .socket(proto: s.type == SOCK_STREAM ? "TCP" : "UDP", local: address(s.local, s.localPort),
                           remote: address(s.remote, s.remotePort), state: state)
        case AF_UNIX where !s.unixPath.isEmpty:
            return .socket(proto: "Unix", local: s.unixPath, remote: "", state: "")
        default:
            return nil
        }
    }

    /// "1.2.3.4:443", "[::1]:8080", "*:53" for any address, "*" for none.
    static func address(_ bytes: [UInt8], _ port: UInt16) -> String {
        guard bytes.contains(where: { $0 != 0 }) else { return port == 0 ? "*" : "*:\(port)" }
        var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let v6 = bytes.count == 16
        _ = bytes.withUnsafeBytes { inet_ntop(v6 ? AF_INET6 : AF_INET, $0.baseAddress, &text, socklen_t(text.count)) }
        let host = String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return v6 ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    /// Each item once, in fd order, cut to `limit`; the `unread` fds count as more.
    static func capped(pid: Int32, _ items: [OpenItem], unread: Int = 0) -> OpenItems {
        var seen = Set<OpenItem>()
        let unique = items.filter { seen.insert($0).inserted }
        return OpenItems(pid: pid, items: Array(unique.prefix(limit)), more: max(0, unique.count - limit) + unread)
    }

    /// The processes of a request (JSON `[ProcessIdentity]`), or nil when it is too large or not valid.
    public static func request(_ data: Data) -> [ProcessIdentity]? {
        guard data.count <= 8192, let ids = try? JSONDecoder().decode([ProcessIdentity].self, from: data),
              ids.count <= maxProcesses, ids.allSatisfy({ $0.pid > 0 }) else { return nil }
        return ids
    }

    /// Nil when the process is gone or its fds cannot be read.
    public static func read(pid: Int32) -> OpenItems? {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return nil }
        // Room for fds opened since the size call.
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + 16)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard got > 0 else { return nil }
        // Each fd costs a call: read the fds the list can show, plus a margin for repeats and fds it skips.
        let all = fds.prefix(Int(got) / stride), first = all.prefix(limit + 64)
        let items = first.compactMap { fd -> OpenItem? in
            switch Int32(fd.proc_fdtype) {
            case PROX_FDTYPE_VNODE:
                var info = vnode_fdinfowithpath()
                let n = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, Int32(MemoryLayout.size(ofValue: info)))
                let path = withUnsafeBytes(of: info.pvip.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                return n > 0 && !path.isEmpty ? .file(path: path) : nil
            case PROX_FDTYPE_SOCKET:
                var info = socket_fdinfo()
                guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout.size(ofValue: info))) > 0
                else { return nil }
                return item(socket(info.psi))
            default:
                return nil
            }
        }
        return capped(pid: pid, items, unread: all.count - first.count)
    }

    private static func socket(_ si: socket_info) -> Socket {
        var s = Socket(family: si.soi_family, type: si.soi_type)
        switch Int(si.soi_kind) {
        case SOCKINFO_IN, SOCKINFO_TCP:
            let tcp = Int(si.soi_kind) == SOCKINFO_TCP
            let ini = tcp ? si.soi_proto.pri_tcp.tcpsi_ini : si.soi_proto.pri_in
            let v4 = ini.insi_vflag & UInt8(INI_IPV4) != 0
            func bytes(_ a: in4in6_addr, _ a6: in6_addr) -> [UInt8] {
                v4 ? withUnsafeBytes(of: a.i46a_addr4) { Array($0) } : withUnsafeBytes(of: a6) { Array($0) }
            }
            s.local = bytes(ini.insi_laddr.ina_46, ini.insi_laddr.ina_6)
            s.remote = bytes(ini.insi_faddr.ina_46, ini.insi_faddr.ina_6)
            // Ports are in network order in the low 16 bits.
            s.localPort = UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_lport))
            s.remotePort = UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_fport))
            if tcp { s.tcpState = si.soi_proto.pri_tcp.tcpsi_state }
        case SOCKINFO_UN:
            var addr = si.soi_proto.pri_un.unsi_addr.ua_sun
            s.unixPath = withUnsafeBytes(of: &addr.sun_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        default:
            break
        }
        return s
    }
}
