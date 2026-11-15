import Foundation

public actor ProbeCaches {
    public let codesign: CodesignCache
    public let plist: PlistContentCache
    public let mdfind: MdfindCache
    public let launchctl: LaunchctlCache
    public let backgroundItems: BackgroundItemsCache

    public init(
        codesign: CodesignCache = CodesignCache(),
        plist: PlistContentCache = PlistContentCache(),
        mdfind: MdfindCache = MdfindCache(),
        launchctl: LaunchctlCache = LaunchctlCache(),
        backgroundItems: BackgroundItemsCache = BackgroundItemsCache()
    ) {
        self.codesign = codesign
        self.plist = plist
        self.mdfind = mdfind
        self.launchctl = launchctl
        self.backgroundItems = backgroundItems
    }
}
