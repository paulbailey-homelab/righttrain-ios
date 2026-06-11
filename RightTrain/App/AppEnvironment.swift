import SwiftUI

extension View {
    @MainActor
    func rightTrainAppEnvironment(_ appCoordinator: AppCoordinator) -> some View {
        self
            .environment(appCoordinator)
            .environment(appCoordinator.operationState)
            .environment(appCoordinator.authViewModel)
            .environment(appCoordinator.windowSetupViewModel)
            .environment(appCoordinator.commuteRoutinesViewModel)
            .environment(appCoordinator.activeWindowViewModel)
            .environment(appCoordinator.journeyDetailViewModel)
            .environment(appCoordinator.notificationViewModel)
            .environment(appCoordinator.subscriptionViewModel)
            .environment(appCoordinator.connectivityService)
            .environment(appCoordinator.journeyMutationQueue)
    }
}
