import Foundation
import Observation

/// Long-lived workspace state container anchored in `RootView` so tab switches
/// and language reloads preserve cached scan results without re-scanning.
@MainActor
@Observable
final class WorkspaceStore {
    let dashboardViewModel: DashboardViewModel
    let diskAnalyzerViewModel: DiskAnalyzerViewModel
    let duplicatesViewModel: DuplicatesViewModel
    let processesViewModel: ProcessesViewModel
    let startupServicesViewModel: StartupServicesViewModel
    let privacyViewModel: PrivacyViewModel
    let uninstallerViewModel: UninstallerViewModel

    init(journal: TransactionJournal) {
        self.dashboardViewModel = DashboardViewModel(journal: journal)
        self.diskAnalyzerViewModel = DiskAnalyzerViewModel()
        self.duplicatesViewModel = DuplicatesViewModel()
        self.processesViewModel = ProcessesViewModel()
        self.startupServicesViewModel = StartupServicesViewModel()
        self.privacyViewModel = PrivacyViewModel()
        self.uninstallerViewModel = UninstallerViewModel()
    }
}
