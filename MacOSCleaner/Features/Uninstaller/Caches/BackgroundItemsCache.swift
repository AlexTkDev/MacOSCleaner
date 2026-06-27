import Foundation

public actor BackgroundItemsCache {
    private var launchAgents: Set<URL> = []
    private var loginItems: Set<URL> = []

    public init() {}

    public func getLaunchAgents() -> Set<URL> { launchAgents }
    public func getLoginItems() -> Set<URL> { loginItems }

    public func setLaunchAgents(_ urls: Set<URL>) { launchAgents = urls }
    public func setLoginItems(_ urls: Set<URL>) { loginItems = urls }

    public func warmup() async {
        let reader = BackgroundItemsReader()
        launchAgents = await reader.readLaunchAgents()
        loginItems = await reader.readLoginItems()
    }
}
