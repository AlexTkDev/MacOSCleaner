import Foundation

/// Inspects a `.zip` archive's Central Directory without extracting any payload.
enum ZipCentralDirectoryInspector {
    static let minimumInstallerZipBytes: Int64 = 50 * 1024 * 1024
    private static let maxTailScanBytes = 65_557 // 22-byte EOCD + 65,535-byte max comment
    private static let maxCentralDirectoryBytes = 16 * 1024 * 1024
    private static let maxEntryCount = 100_000

    static func containsInstallerPayload(at path: String, fileSize: Int64? = nil) -> Bool {
        let resolvedSize: Int64
        if let fileSize {
            resolvedSize = fileSize
        } else if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let attrSize = attrs[.size] as? NSNumber {
            resolvedSize = attrSize.int64Value
        } else {
            return false
        }
        guard resolvedSize > minimumInstallerZipBytes else { return false }

        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return false
        }
        defer { try? handle.close() }

        let totalSize = UInt64(resolvedSize)
        let tailLength = min(totalSize, UInt64(maxTailScanBytes))
        let tailOffset = totalSize - tailLength
        guard (try? handle.seek(toOffset: tailOffset)) != nil,
              let tailData = try? handle.read(upToCount: Int(tailLength)),
              tailData.count >= 22 else {
            return false
        }

        guard let eocdIdx = findEOCDOffset(in: tailData) else { return false }

        var cdOffset = UInt64(readUInt32LE(tailData, at: eocdIdx + 16))
        var cdSize = UInt64(readUInt32LE(tailData, at: eocdIdx + 12))
        var entryCount = UInt64(readUInt16LE(tailData, at: eocdIdx + 10))

        // Support ZIP64 archives (> 4 GB or > 65,535 entries).
        if cdOffset == UInt64(UInt32.max) || cdSize == UInt64(UInt32.max) || entryCount == UInt64(UInt16.max) {
            guard eocdIdx >= 20,
                  readUInt32LE(tailData, at: eocdIdx - 20) == 0x0706_4b50 else {
                return false
            }
            let zip64EOCDOffset = readUInt64LE(tailData, at: eocdIdx - 12)
            guard zip64EOCDOffset + 56 <= totalSize,
                  (try? handle.seek(toOffset: zip64EOCDOffset)) != nil,
                  let z64 = try? handle.read(upToCount: 56),
                  z64.count == 56,
                  readUInt32LE(z64, at: 0) == 0x0606_4b50 else {
                return false
            }
            entryCount = readUInt64LE(z64, at: 32)
            cdSize = readUInt64LE(z64, at: 40)
            cdOffset = readUInt64LE(z64, at: 48)
        }

        guard cdSize > 0,
              cdSize <= UInt64(maxCentralDirectoryBytes),
              entryCount <= UInt64(maxEntryCount),
              cdOffset + cdSize <= totalSize else {
            return false
        }

        guard (try? handle.seek(toOffset: cdOffset)) != nil,
              let cdData = try? handle.read(upToCount: Int(cdSize)),
              cdData.count == Int(cdSize) else {
            return false
        }

        return scanCentralDirectory(cdData, maxEntries: Int(entryCount))
    }

    private static func findEOCDOffset(in tail: Data) -> Int? {
        guard tail.count >= 22 else { return nil }
        var idx = tail.count - 22
        while idx >= 0 {
            if tail[idx] == 0x50,
               tail[idx + 1] == 0x4b,
               tail[idx + 2] == 0x05,
               tail[idx + 3] == 0x06 {
                let commentLen = Int(readUInt16LE(tail, at: idx + 20))
                if idx + 22 + commentLen == tail.count {
                    return idx
                }
            }
            idx -= 1
        }
        return nil
    }

    private static func scanCentralDirectory(_ data: Data, maxEntries: Int) -> Bool {
        var offset = 0
        var processed = 0
        while offset + 46 <= data.count && processed < maxEntries {
            guard readUInt32LE(data, at: offset) == 0x0201_4b50 else { break }
            let nameLen = Int(readUInt16LE(data, at: offset + 28))
            let extraLen = Int(readUInt16LE(data, at: offset + 30))
            let commentLen = Int(readUInt16LE(data, at: offset + 32))
            let nameStart = offset + 46
            let nextOffset = nameStart + nameLen + extraLen + commentLen
            guard nextOffset <= data.count else { break }

            let nameSlice = data[nameStart..<(nameStart + nameLen)]
            let name = String(data: nameSlice, encoding: .utf8)
                ?? String(data: nameSlice, encoding: .isoLatin1)
                ?? ""
            let lower = name.lowercased()
            if !lower.hasPrefix("__macosx/"),
               lower.contains(".app/") || lower.hasSuffix(".app") || lower.contains(".pkg/") || lower.hasSuffix(".pkg") {
                return true
            }

            offset = nextOffset
            processed += 1
        }
        return false
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func readUInt64LE(_ data: Data, at offset: Int) -> UInt64 {
        let low = UInt64(readUInt32LE(data, at: offset))
        let high = UInt64(readUInt32LE(data, at: offset + 4))
        return low | (high << 32)
    }
}
