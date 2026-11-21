import Foundation
import Observation

@Observable
public final class StartupServicesViewModel {
    private let manager: LaunchServiceManager

    public var services: [StartupService] = []
    public var loginItems: [StartupService] = []
    public var loginItemsAccess: BackgroundItemsAccessStatus = .available
    public var isLoading: Bool = false
    public var lastError: String? = nil
    public var lastUpdatedAt: Date? = nil
    public var filter: StartupFilter = .all

    public var filteredServices: [StartupService] {
        switch filter {
        case .all:
            return services
        case .needsAttention:
            return services.filter(\.needsAttention)
        case .user:
            return services.filter { $0.category == .user }
        case .thirdParty:
            return services.filter { $0.category == .thirdParty }
        case .system:
            return services.filter { $0.category == .system }
        case .loginItems:
            return loginItems
        }
    }

    public var attentionCount: Int {
        services.filter(\.needsAttention).count
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

    public var loginItemsCount: Int {
        loginItems.count
    }

    public init(manager: LaunchServiceManager = LaunchServiceManager()) {
        self.manager = manager
    }

    @MainActor
    public func scanIfNeeded() async {
        guard lastUpdatedAt == nil, !isLoading else { return }
        await scan()
    }

    @MainActor
    public func scan() async {
        isLoading = true
        lastError = nil
        do {
            let result = try await manager.scanAll()
            services = result.services
            loginItems = result.loginItems
            loginItemsAccess = result.loginItemsAccess
            lastUpdatedAt = Date()
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
            await scan()
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    public func delete(service: StartupService, bypassTrash: Bool = false) async {
        lastError = nil
        do {
            try await manager.delete(service: service, bypassTrash: bypassTrash)
            await scan()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
