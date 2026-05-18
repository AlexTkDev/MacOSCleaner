import Foundation

public struct SystemInfo: Sendable {
    public let model: String
    public let osVersion: String
    public let processor: String
    public let memory: String
    
    public static var current: SystemInfo {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        
        let memoryBytes = ProcessInfo.processInfo.physicalMemory
        let memoryString = ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
        
        return SystemInfo(
            model: getModelIdentifier(),
            osVersion: osString,
            processor: getProcessorName(),
            memory: memoryString
        )
    }
    
    private static func getModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    private static func getProcessorName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let brandString = String(cString: brand)
        if !brandString.isEmpty { return brandString }
        
        // Fallback for Apple Silicon
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
