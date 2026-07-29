import Foundation
@preconcurrency import BackgroundTasks

final class PhoneBackgroundRefreshCoordinator: @unchecked Sendable {
    static let shared = PhoneBackgroundRefreshCoordinator()
    static let taskIdentifier = "com.yinian.Sub2Watch.refresh"

    private weak var model: AppModel?

    private init() {}

    @MainActor
    func register(model: AppModel) {
        self.model = model
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in
                await self?.handle(refreshTask)
            }
        }
        schedule()
    }

    @MainActor
    func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    private func handle(_ task: BGAppRefreshTask) async {
        schedule()
        guard let model, model.configuration != nil else {
            task.setTaskCompleted(success: true)
            return
        }

        let refresh = Task { @MainActor in
            await model.refreshDashboard()
            return !Task.isCancelled
        }
        task.expirationHandler = {
            refresh.cancel()
        }
        task.setTaskCompleted(success: await refresh.value)
    }
}
