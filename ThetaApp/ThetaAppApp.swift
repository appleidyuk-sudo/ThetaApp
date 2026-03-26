// ThetaAppApp.swift — App entry point
// The Wheel strategy simulator

import SwiftUI
import BackgroundTasks

@main
struct ThetaAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var config = ThetaConfig()
    @StateObject private var store: ThetaStore

    init() {
        let cfg = ThetaConfig()
        _config = StateObject(wrappedValue: cfg)
        _store = StateObject(wrappedValue: ThetaStore(config: cfg))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(config)
                .onAppear {
                    NotificationManager.shared.requestPermission()
                    if config.autoExecute {
                        store.startAutoExecution()
                    }
                }
        }
    }
}

// MARK: - AppDelegate for Background Refresh

class AppDelegate: NSObject, UIApplicationDelegate {
    static let bgTaskIdentifier = "com.dhcdigital.ThetaAppMistro.wheelRefresh"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgTaskIdentifier,
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        scheduleAppRefresh()
        return true
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        let interval = UserDefaults.standard.integer(forKey: "refreshInterval")
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(max(interval, 15) * 60))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("BG task schedule error: \(error)")
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule next refresh
        scheduleAppRefresh()

        let bgTask = Task {
            let config = ThetaConfig()
            let store = ThetaStore(config: config)

            // Only execute if auto-execute is enabled
            guard config.autoExecute else {
                task.setTaskCompleted(success: true)
                return
            }

            await store.executeWheelCycle()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            bgTask.cancel()
        }
    }
}
