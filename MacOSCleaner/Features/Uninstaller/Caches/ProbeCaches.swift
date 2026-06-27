import Foundation

public actor ProbeCaches {
    public let codesign: CodesignCache
    public let plist: PlistContentCache
    public let identity: IdentityCache
    public let mdfind: MdfindCache
    public let launchctl: LaunchctlCache
    public let backgroundItems: BackgroundItemsCache

    public init(
        codesign: CodesignCache = CodesignCache(),
        plist: PlistContentCache = PlistContentCache(),
        identity: IdentityCache = IdentityCache(),
        mdfind: MdfindCache = MdfindCache(),
        launchctl: LaunchctlCache = LaunchctlCache(),
        backgroundItems: BackgroundItemsCache = BackgroundItemsCache()
    ) {
        self.codesign = codesign
        self.plist = plist
        self.identity = identity
        self.mdfind = mdfind
        self.launchctl = launchctl
        self.backgroundItems = backgroundItems
    }
}
