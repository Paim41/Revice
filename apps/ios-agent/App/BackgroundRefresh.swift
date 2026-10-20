import BackgroundTasks
import UIKit

@MainActor final class BackgroundRefresh {
    static let shared = BackgroundRefresh()
    static let identifier = "app.revice.ios-agent.refresh"
    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in self.run(refresh) }
        }
    }
    func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
        guard AgentModel.shared.paired, AgentModel.shared.state.backgroundEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        // Earliest eligibility is not a promised interval. iOS decides if/when to run.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { AgentModel.shared.message = "Background refresh is unavailable. Open Revice to synchronize." }
    }
    private func run(_ task: BGAppRefreshTask) {
        schedule()
        let operation = Task { @MainActor in
            guard AgentModel.shared.state.backgroundEnabled, AgentModel.shared.paired else {
                task.setTaskCompleted(success: false); return
            }
            let success = await AgentModel.shared.sync()
            task.setTaskCompleted(success: success && !Task.isCancelled)
        }
        task.expirationHandler = { operation.cancel() }
    }
}
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRefresh.shared.register(); return true
    }
}
