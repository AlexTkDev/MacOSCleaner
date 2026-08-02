// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import Foundation

public struct DuplicateFileItem: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let url: URL
    public let path: String
    public let name: String
    public let sizeBytes: Int64
    public let modificationDate: Date?
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        sizeBytes: Int64,
        modificationDate: Date? = nil,
        isSelected: Bool = false
    ) {
        self.id = id
        self.url = url
        self.path = url.path
        self.name = url.lastPathComponent
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
        self.isSelected = isSelected
    }
}

public struct DuplicateGroup: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let fileSize: Int64
    public let hashValue: String
    public var items: [DuplicateFileItem]

    public var selectedWastedBytes: Int64 {
        let selectedItems = items.filter(\.isSelected)
        return Int64(selectedItems.count) * fileSize
    }

    public var potentialWastedBytes: Int64 {
        guard items.count > 1 else { return 0 }
        return Int64(items.count - 1) * fileSize
    }

    public init(
        id: UUID = UUID(),
        fileSize: Int64,
        hashValue: String,
        items: [DuplicateFileItem]
    ) {
        self.id = id
        self.fileSize = fileSize
        self.hashValue = hashValue
        self.items = items
    }
}

public enum SmartSelectStrategy: String, CaseIterable, Identifiable, Sendable {
    case keepOldest
    case keepNewest
    case selectAll
    case deselectAll

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .keepOldest: return "duplicate_select_keep_oldest".localized
        case .keepNewest: return "duplicate_select_keep_newest".localized
        case .selectAll: return "duplicate_select_all".localized
        case .deselectAll: return "duplicate_deselect_all".localized
        }
    }
}
