// ContentView.swift — Main tab navigation

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ThetaStore
    @EnvironmentObject var config: ThetaConfig

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Dashboard")
                }

            WatchlistView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Positions")
                }

            BacktestView()
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Backtest")
                }

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
        }
        .tint(AppColors.gold)
        .preferredColorScheme(.dark)
        .onAppear {
            // Style tab bar for dark theme
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1.0)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
