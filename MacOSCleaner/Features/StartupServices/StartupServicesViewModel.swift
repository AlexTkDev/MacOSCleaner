import Foundation
import Observation

@Observable
public final class StartupServicesViewModel {
    private let manager: LaunchServiceManager

    public var services: [StartupService] = []
    public var isLoading: Bool = false
    public var lastError: String? = nil
    public var filter: ServiceCategory? = nil

    public var filteredServices: [StartupService] {
        guard let filter else { return services }
        return services.filter { $0.category == filter }
    }

    public var userCount: Int {
        services.filter { $0.category == .user }.count
    }

    public var thirdPartyCount: Int {
        services.filter { $0.category == .thirdParty }.count
    }

    public var systemCount: Int {
        services.filter { $0.category == .system }.count
    }

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
            services = try await manager.scan()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
