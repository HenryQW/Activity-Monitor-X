// MIT License. See Packaging/Credits.html.
import Foundation
import IOKit

struct Temperatures: Equatable {
    var cpu: Double?
    var gpu: Double?
    var ssd: Double?
}

/// Apple silicon temperatures from the AppleSMC user client. Keys are discovered by
/// name and type, never from a per-chip table. Root is not needed.
final class SMCReader {
    enum Group { case cpu, gpu, ssd }

    private var connection: io_connect_t = 0
    private var didOpen = false
    private var keys: [(key: UInt32, group: Group, info: SMCKeyInfoData)] = []
    private var lastDiscovery: Double?

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// Hottest sensor per group; keys rediscovered every hour once the SSD's is found, else every 5 minutes (a failed key
    /// list or an SSD sensor that reads 0 at boot finds nothing on the first pass).
    func read(now: Double) -> Temperatures {
        guard open() else { return Temperatures() }
        let every = keys.contains { $0.group == .ssd } ? 3600.0 : 300
        if lastDiscovery.map({ !(0..<every).contains(now - $0) }) ?? true {
            discover()
            lastDiscovery = now
        }
        var t = Temperatures()
        for (key, group, info) in keys {
            guard let v = readValue(key, info: info), Self.isValid(v) else { continue }
            switch group {
            case .cpu: t.cpu = max(t.cpu ?? v, v)
            case .gpu: t.gpu = max(t.gpu ?? v, v)
            case .ssd: t.ssd = max(t.ssd ?? v, v)
            }
        }
        return t
    }

    /// Case matters: `Tg*` is the GPU while `TG0*` is battery-adjacent.
    static func group(forKey name: String) -> Group? {
        if name.hasPrefix("Tp") || name.hasPrefix("Te") { return .cpu }
        if name.hasPrefix("Tg") { return .gpu }
        if name.hasPrefix("TH0") { return .ssd }
        return nil
    }

    static func isValid(_ celsius: Double) -> Bool { celsius > 1 && celsius < 130 }

    /// Decodes an exact-size SMC scalar. `ioft` is 64-bit little-endian fixed point
    /// with 16 fraction bits; `flt ` is little-endian, `ui16` big-endian.
    static func decode(type: String, bytes: [UInt8]) -> Double? {
        guard byteCount(forType: type) == bytes.count else { return nil }
        switch type {
        case "flt ":
            let bits = bytes.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            let v = Double(Float(bitPattern: bits))
            return v.isFinite ? v : nil
        case "ioft":
            return Double(bytes.reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }) / 65536
        case "ui16":
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default:
            return Double(bytes[0])
        }
    }

    private static func byteCount(forType type: String) -> Int? {
        ["flt ": 4, "ioft": 8, "ui16": 2, "ui8 ": 1][type]
    }

    // MARK: - Discovery

    /// Merges newly found keys so a failed rescan never drops known ones. Die keys
    /// (CPU, GPU) are kept on valid metadata alone: a zero first read must not exclude
    /// them for the reader's lifetime. SSD keys need a plausible first value.
    private func discover() {
        var known = Set(keys.map(\.key))
        guard let total = readKey(Self.fourCC("#KEY")), total.bytes.count >= 4 else { return }
        let count = total.bytes.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        for index in 0..<count {
            var input = SMCParamStruct()
            input.data8 = 8  // kSMCGetKeyFromIndex
            input.data32 = index
            guard let key = call(&input)?.key, !known.contains(key),
                  let group = Self.group(forKey: Self.toString(key)),
                  let info = readKeyInfo(key),
                  Self.byteCount(forType: Self.toString(info.dataType)) == Int(info.dataSize) else { continue }
            if group == .ssd {
                guard let v = readValue(key, info: info), v > 10, v < 110 else { continue }
            }
            keys.append((key, group, info))
            known.insert(key)
        }
    }

    // MARK: - SMC protocol

    private func open() -> Bool {
        if didOpen { return connection != 0 }
        didOpen = true
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess
    }

    private func readValue(_ key: UInt32, info: SMCKeyInfoData) -> Double? {
        guard let raw = readKey(key, info: info) else { return nil }
        return Self.decode(type: raw.type, bytes: raw.bytes)
    }

    private func readKey(_ key: UInt32) -> (type: String, bytes: [UInt8])? {
        readKeyInfo(key).flatMap { readKey(key, info: $0) }
    }

    private func readKeyInfo(_ key: UInt32) -> SMCKeyInfoData? {
        var input = SMCParamStruct()
        input.key = key
        input.data8 = 9  // kSMCGetKeyInfo
        guard let out = call(&input), out.keyInfo.dataSize > 0,
              out.keyInfo.dataSize <= UInt32(MemoryLayout<SMCBytes>.size) else { return nil }
        return out.keyInfo
    }

    private func readKey(_ key: UInt32, info: SMCKeyInfoData) -> (type: String, bytes: [UInt8])? {
        var input = SMCParamStruct()
        input.key = key
        input.keyInfo = info
        input.data8 = 5  // kSMCReadKey
        guard let out = call(&input) else { return nil }
        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return (Self.toString(info.dataType), bytes)
    }

    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var size = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParamStruct>.stride,
                                               &output, &size)
        // A truncated response or a nonzero SMC result is not a successful read.
        guard result == kIOReturnSuccess, size == MemoryLayout<SMCParamStruct>.stride, output.result == 0
        else { return nil }
        return output
    }

    static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    static func toString(_ v: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8(v >> $0 & 0xff) }, encoding: .ascii) ?? ""
    }
}

// MARK: - Kernel SMCParamStruct layout (80 bytes)

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

/// `padding` is load-bearing: Swift packs `keyInfo` tighter than C, and without it
/// the struct is 76 bytes and the kernel rejects the call with kIOReturnBadArgument.
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}
