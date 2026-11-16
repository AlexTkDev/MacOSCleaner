import Darwin
import Foundation
import OSLog

private extension Logger {
    static let networkSnapshot = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "input.MacOSCleaner",
        category: "NetworkSnapshotService"
    )
}

public actor NetworkSnapshotService {
    private let processInfoProvider: ProcessInfoProvider
    private let fileManager: FileManager
    private let appDiscovery: AppDiscovery

    public init(
        processInfoProvider: ProcessInfoProvider = ProcessInfoProvider(),
        fileManager: FileManager = .default,
        appDiscovery: AppDiscovery = AppDiscovery()
    ) {
        self.processInfoProvider = processInfoProvider
        self.fileManager = fileManager
        self.appDiscovery = appDiscovery
    }

    public func captureSnapshot(includeStaticApps: Bool = true) async throws -> NetworkSnapshot {
        let currentUID = getuid()
        let processes = try await processInfoProvider.listAllProcesses()

        var items: [AppNetworkItem] = []
        var restrictedCount = 0
        var activeSocketsTotal = 0
        var runningBundleURLs = Set<URL>()

        for proc in processes {
            let bundleURL = proc.path.flatMap { Self.enclosingAppBundleURL(fromExecutablePath: $0) }
            if let bundleURL {
                runningBundleURLs.insert(NormalizedPath.url(bundleURL))
            }
            let staticProfile = bundleURL.flatMap { Self.inspectStaticProfile(at: $0, fileManager: fileManager) }

            if let uid = proc.uid, uid != currentUID {
                restrictedCount += 1
                items.append(AppNetworkItem(
                    id: "pid|\(proc.pid)",
                    pid: proc.pid,
                    name: proc.name,
                    bundleID: proc.bundleID,
                    bundleURL: bundleURL,
                    uid: uid,
                    isRunning: true,
                    isRestrictedByPermissions: true,
                    sockets: [],
                    staticProfile: staticProfile
                ))
                continue
            }

            switch Self.readSockets(for: proc.pid) {
            case .restricted:
                restrictedCount += 1
                items.append(AppNetworkItem(
                    id: "pid|\(proc.pid)",
                    pid: proc.pid,
                    name: proc.name,
                    bundleID: proc.bundleID,
                    bundleURL: bundleURL,
                    uid: proc.uid,
                    isRunning: true,
                    isRestrictedByPermissions: true,
                    sockets: [],
                    staticProfile: staticProfile
                ))
            case .sockets(let sockets):
                guard !sockets.isEmpty else { continue }
                activeSocketsTotal += sockets.count
                items.append(AppNetworkItem(
                    id: "pid|\(proc.pid)",
                    pid: proc.pid,
                    name: proc.name,
                    bundleID: proc.bundleID,
                    bundleURL: bundleURL,
                    uid: proc.uid,
                    isRunning: true,
                    isRestrictedByPermissions: false,
                    sockets: sockets,
                    staticProfile: staticProfile
                ))
            }
        }

        if includeStaticApps {
            let apps = await appDiscovery.findAll()
            for appURL in apps {
                let normalized = NormalizedPath.url(appURL)
                guard !runningBundleURLs.contains(normalized) else { continue }
                guard let profile = Self.inspectStaticProfile(at: appURL, fileManager: fileManager),
                      profile.hasAnyCapability else { continue }
                let bundle = Bundle(url: appURL)
                let name = (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
                    ?? appURL.deletingPathExtension().lastPathComponent
                items.append(AppNetworkItem(
                    id: "app|\(normalized.path)",
                    pid: nil,
                    name: name,
                    bundleID: bundle?.bundleIdentifier,
                    bundleURL: appURL,
                    uid: nil,
                    isRunning: false,
                    isRestrictedByPermissions: false,
                    sockets: [],
                    staticProfile: profile
                ))
            }
        }

        items.sort { lhs, rhs in
            if lhs.sockets.count != rhs.sockets.count {
                return lhs.sockets.count > rhs.sockets.count
            }
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return NetworkSnapshot(
            capturedAt: Date(),
            currentUID: currentUID,
            items: items,
            restrictedProcessCount: restrictedCount,
            activeSocketCount: activeSocketsTotal
        )
    }

    // MARK: - libproc Socket Inspection

    enum SocketReadResult {
        case restricted
        case sockets([NetworkSocketItem])
    }

    static func readSockets(for pid: pid_t) -> SocketReadResult {
        let fdBufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        if fdBufferSize <= 0 {
            let err = errno
            if err == EPERM || err == EACCES {
                return .restricted
            }
            return .sockets([])
        }

        let fdStride = MemoryLayout<proc_fdinfo>.stride
        let count = Int(fdBufferSize) / fdStride
        guard count > 0 else { return .sockets([]) }

        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: count)
        let actualBytes = proc_pidinfo(
            pid,
            PROC_PIDLISTFDS,
            0,
            &fds,
            Int32(count * fdStride)
        )
        if actualBytes <= 0 {
            let err = errno
            if err == EPERM || err == EACCES {
                return .restricted
            }
            return .sockets([])
        }

        let actualCount = Int(actualBytes) / fdStride
        var sockets: [NetworkSocketItem] = []
        var seen = Set<String>()

        for i in 0..<actualCount {
            let fd = fds[i]
            guard fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) else { continue }

            var socketInfo = socket_fdinfo()
            let infoSize = proc_pidfdinfo(
                pid,
                fd.proc_fd,
                PROC_PIDFDSOCKETINFO,
                &socketInfo,
                Int32(MemoryLayout<socket_fdinfo>.size)
            )
            guard infoSize == Int32(MemoryLayout<socket_fdinfo>.size) else { continue }

            if let item = parseSocketInfo(socketInfo.psi), seen.insert(item.id).inserted {
                sockets.append(item)
            }
        }

        return .sockets(sockets)
    }

    private static func parseSocketInfo(_ psi: socket_info) -> NetworkSocketItem? {
        switch psi.soi_kind {
        case Int32(SOCKINFO_TCP):
            let tcpInfo = psi.soi_proto.pri_tcp
            let ini = tcpInfo.tcpsi_ini
            let local = endpoint(from: ini, isRemote: false)
            let remote = endpoint(from: ini, isRemote: true)
            let state = tcpStateName(tcpInfo.tcpsi_state)
            let effectiveRemote = (remote.port == 0 && (remote.address == "0.0.0.0" || remote.address == "::")) ? nil : remote
            return NetworkSocketItem(
                proto: .tcp,
                local: local,
                remote: effectiveRemote,
                state: state
            )
        case Int32(SOCKINFO_IN):
            let ini = psi.soi_proto.pri_in
            let proto: SocketProtocol
            switch psi.soi_protocol {
            case IPPROTO_TCP: proto = .tcp
            case IPPROTO_UDP: proto = .udp
            default: return nil
            }
            let local = endpoint(from: ini, isRemote: false)
            let remote = endpoint(from: ini, isRemote: true)
            let effectiveRemote = (remote.port == 0 && (remote.address == "0.0.0.0" || remote.address == "::")) ? nil : remote
            return NetworkSocketItem(
                proto: proto,
                local: local,
                remote: effectiveRemote,
                state: nil
            )
        default:
            return nil
        }
    }

    private static func endpoint(from ini: in_sockinfo, isRemote: Bool) -> SocketEndpoint {
        let rawPort = isRemote ? ini.insi_fport : ini.insi_lport
        let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: rawPort))
        let isIPv6 = (ini.insi_vflag & UInt8(INI_IPV6)) != 0

        if isIPv6 {
            var addr6 = isRemote ? ini.insi_faddr.ina_6 : ini.insi_laddr.ina_6
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let ptr = withUnsafePointer(to: &addr6) {
                inet_ntop(AF_INET6, $0, &buffer, socklen_t(INET6_ADDRSTRLEN))
            }
            let addrStr = ptr.map { String(cString: $0) } ?? "::"
            return SocketEndpoint(address: addrStr, port: port)
        } else {
            var addr4 = isRemote ? ini.insi_faddr.ina_46.i46a_addr4 : ini.insi_laddr.ina_46.i46a_addr4
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let ptr = withUnsafePointer(to: &addr4) {
                inet_ntop(AF_INET, $0, &buffer, socklen_t(INET_ADDRSTRLEN))
            }
            let addrStr = ptr.map { String(cString: $0) } ?? "0.0.0.0"
            return SocketEndpoint(address: addrStr, port: port)
        }
    }

    private static func tcpStateName(_ state: Int32) -> String {
        switch state {
        case TSI_S_CLOSED: return "CLOSED"
        case TSI_S_LISTEN: return "LISTEN"
        case TSI_S_SYN_SENT: return "SYN_SENT"
        case TSI_S_SYN_RECEIVED: return "SYN_RCVD"
        case TSI_S_ESTABLISHED: return "ESTABLISHED"
        case TSI_S__CLOSE_WAIT: return "CLOSE_WAIT"
        case TSI_S_FIN_WAIT_1: return "FIN_WAIT_1"
        case TSI_S_CLOSING: return "CLOSING"
        case TSI_S_LAST_ACK: return "LAST_ACK"
        case TSI_S_FIN_WAIT_2: return "FIN_WAIT_2"
        case TSI_S_TIME_WAIT: return "TIME_WAIT"
        default: return "STATE(\(state))"
        }
    }

    // MARK: - Static Bundle Network Inspection

    public static func inspectStaticProfile(
        at bundleURL: URL,
        fileManager: FileManager = .default
    ) -> StaticNetworkProfile? {
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        let ats = plist["NSAppTransportSecurity"] as? [String: Any]
        let arbitraryLoads = ats?["NSAllowsArbitraryLoads"] as? Bool ?? false
        let exceptionDict = ats?["NSExceptionDomains"] as? [String: Any]
        let exceptionDomains = exceptionDict.map { Array($0.keys).sorted() } ?? []

        var urlSchemes: [String] = []
        if let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]] {
            for typeEntry in urlTypes {
                if let schemes = typeEntry["CFBundleURLSchemes"] as? [String] {
                    urlSchemes.append(contentsOf: schemes)
                }
            }
        }
        let uniqueSchemes = Array(Set(urlSchemes.filter { !$0.isEmpty })).sorted()

        let helperSubdirs = [
            "Contents/Library/LaunchServices",
            "Contents/XPCServices",
            "Contents/Library/LoginItems",
            "Contents/Helpers",
        ]
        var helpers: [String] = []
        for subdir in helperSubdirs {
            let dirURL = bundleURL.appendingPathComponent(subdir, isDirectory: true)
            if let contents = try? fileManager.contentsOfDirectory(atPath: dirURL.path) {
                helpers.append(contentsOf: contents.filter { !$0.hasPrefix(".") })
            }
        }
        let uniqueHelpers = Array(Set(helpers)).sorted()

        return StaticNetworkProfile(
            atsAllowsArbitraryLoads: arbitraryLoads,
            atsExceptionDomains: exceptionDomains,
            urlSchemes: uniqueSchemes,
            helperServices: uniqueHelpers
        )
    }

    static func enclosingAppBundleURL(fromExecutablePath path: String) -> URL? {
        var current = URL(fileURLWithPath: path)
        while current.path != "/" {
            if current.pathExtension.lowercased() == "app" {
                return current
            }
            current.deleteLastPathComponent()
        }
        return nil
    }
}
