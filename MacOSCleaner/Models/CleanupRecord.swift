// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import Foundation

public typealias CleanupTrigger = CleanupRecord.Trigger
public typealias CleanupHistoryCategory = CleanupRecord.Category

public struct CleanupRecord: Identifiable, Codable, Sendable, Equatable {
    public typealias CleanupCategory = Category

    public enum Trigger: String, Codable, CaseIterable, Sendable {
        case manual = "manual"
        case automatic = "automatic"
        
        public var localizedTitle: String {
            switch self {
            case .manual:
                return "history_trigger_manual".localized
            case .automatic:
                return "history_trigger_automatic".localized
            }
        }
    }

    public enum Category: String, Codable, CaseIterable, Sendable {
        case general = "general"
        case media = "media"
        case caches = "caches"
        case dev = "dev"
        
        public var iconName: String {
            switch self {
            case .general:
                return "paintbrush"
            case .media:
                return "photo.on.rectangle"
            case .caches:
                return "gearshape.2"
            case .dev:
                return "hammer"
            }
        }
        
        public var localizedTitle: String {
            switch self {
            case .general:
                return "history_category_general".localized
            case .media:
                return "history_category_media".localized
            case .caches:
                return "history_category_caches".localized
            case .dev:
                return "history_category_dev".localized
            }
        }
    }

    public let id: UUID
    public let date: Date
    public let freedBytes: Int64
    public let trigger: Trigger
    public let category: Category
    
    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        freedBytes: Int64,
        trigger: Trigger = .manual,
        category: Category = .general
    ) {
        self.id = id
        self.date = date
        self.freedBytes = freedBytes
        self.trigger = trigger
        self.category = category
    }
    
    public var formattedSize: String {
        "+\(freedBytes.formattedByteCount())"
    }
}

public extension CleanupRecord {
    init(transaction: CleanupTransaction) {
        self.id = transaction.id
        self.date = transaction.timestamp
        self.freedBytes = transaction.operations.reduce(0) { $0 + $1.bytesFreed }
        
        var inferredCategory: Category = .general
        for op in transaction.operations {
            let path = op.itemPath.lowercased()
            if path.contains("developer") || path.contains("xcode") || path.contains("android") || path.contains("gradle") || path.contains("deriveddata") {
                inferredCategory = .dev
                break
            } else if path.contains("music") || path.contains("movies") || path.contains("pictures") || path.contains("photos") {
                inferredCategory = .media
                break
            } else if path.contains("cache") || path.contains("logs") {
                inferredCategory = .caches
            }
        }
        self.category = inferredCategory
        self.trigger = .manual
    }
}
