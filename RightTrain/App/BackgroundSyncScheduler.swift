import BackgroundTasks
import Foundation

final class BackgroundSyncScheduler {
    static let shared = BackgroundSyncScheduler()
    static let identifier = "com.righttrain.ios.journey-sync"

    private var didRegister = false

    private init() {}

    func register(handler: @escaping @MainActor () async -> Void) {
        guard !didRegister else { return }
        didRegister = true
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { task in
            self.handle(task, handler: handler)
        }
        if !registered {
            BetaDiagnostics.record("background_sync_registration_failed")
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date().addingTimeInterval(60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            BetaDiagnostics.record("background_sync_schedule_failed", details: error.localizedDescription)
        }
    }

    private func handle(_ task: BGTask, handler: @escaping @MainActor () async -> Void) {
        schedule()
        let syncTask = Task {
            await handler()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
