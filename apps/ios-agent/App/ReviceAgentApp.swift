import SwiftUI

@main struct ReviceAgentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AgentModel.shared
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            AgentRoot(model: model)
                .preferredColorScheme(.dark)
                .tint(Volt.lime)
                .onChange(of: phase) { _, next in
                    if next == .active { Task { await model.foreground() } }
                    if next == .background { BackgroundRefresh.shared.schedule() }
                }
        }
    }
}
