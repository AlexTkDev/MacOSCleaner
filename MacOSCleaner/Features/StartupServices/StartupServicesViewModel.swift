import Foundation
import Observation

@Observable
public final class StartupServicesViewModel {
    private let manager: LaunchServiceManager
    
    public var services: [StartupService] = []
    public var isLoading: Bool = false
    public var lastError: String? = nil
    
    public init(manager: LaunchServiceManager = LaunchServiceManager()) {
        self.manager = manager
    }
    
    @MainActor
    public func scan() async {
        isLoading = true
        lastError = nil
        do {
            services = try await manager.scan()
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }
    
    @MainActor
    public func toggle(service: StartupService) async {
        lastError = nil
        do {
            if service.isEnabled {
                try await manager.disable(service: service)
            } else {
                try await manager.enable(service: service)
            }
            // Refresh to get actual state from launchctl
            services = try await manager.scan()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
