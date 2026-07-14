import Foundation

public enum FileCategory: String, CaseIterable, Sendable {
    case all
    case video
    case audio
    case apps
    case docs
    case archives
    case dev
    case other
    
    public var localizedName: String {
        switch self {
        case .all: return "disk_analyzer_category_all".localized
        case .video: return "disk_analyzer_category_video".localized
        case .audio: return "disk_analyzer_category_audio".localized
        case .apps: return "disk_analyzer_category_apps".localized
        case .docs: return "disk_analyzer_category_docs".localized
        case .archives: return "disk_analyzer_category_archives".localized
        case .dev: return "disk_analyzer_category_dev".localized
        case .other: return "disk_analyzer_category_other".localized
        }
    }
    
    public static func from(url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "mov", "avi", "m4v", "webm", "flv":
            return .video
        case "mp3", "wav", "flac", "m4a", "aac", "ogg", "wma":
            return .audio
        case "app", "dmg", "pkg", "ipa":
            return .apps
        case "pdf", "docx", "doc", "txt", "xlsx", "xls", "pptx", "ppt", "pages", "numbers", "key", "rtf", "odt":
            return .docs
        case "zip", "tar", "gz", "rar", "7z", "bz2", "xz":
            return .archives
        case "swift", "py", "java", "c", "cpp", "h", "js", "ts", "json", "yaml", "yml", "sh", "html", "css", "go", "rs", "kt":
            return .dev
        default:
            return .other
        }
    }
}

public struct DiskItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public var size: Int64
    public var children: [DiskItem]?
    public let fileType: FileCategory
    
    public init(id: UUID = UUID(), url: URL, name: String, isDirectory: Bool, size: Int64, children: [DiskItem]? = nil, fileType: FileCategory) {
        self.id = id
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.children = children
        self.fileType = fileType
    }
}
