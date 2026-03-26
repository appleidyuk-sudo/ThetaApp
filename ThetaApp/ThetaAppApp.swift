// ThetaAppApp.swift — App entry point
// The Wheel strategy simulator

import SwiftUI

@main
struct ThetaAppApp: App {
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
                    if config.autoExecute {
                        store.startAutoExecution()
                    }
                }
        }
    }
}
