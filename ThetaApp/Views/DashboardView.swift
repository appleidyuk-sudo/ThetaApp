// DashboardView.swift — Portfolio dashboard / home screen
// DHCbot-style dark gradient with cards

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: ThetaStore
    @EnvironmentObject var config: ThetaConfig
    @State private var showHelp = false
    @State private var showPauseWarning = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    headerSection
                    portfolioCards
                    wheelStatusSection
                    recentTradesSection
                }
                .padding()
            }
        }
        .refreshable { await store.refreshPrices() }
        .sheet(isPresented: $showHelp) { HelpSheet(screen: .dashboard) }
        .alert("Pause Auto-Execute?", isPresented: $showPauseWarning) {
            Button("Keep Running", role: .cancel) {}
            Button("Pause", role: .destructive) {
                store.stopAutoExecution()
            }
        } message: {
            Text("Rolls, new writes, and expiration handling will not run automatically. You'll need to tap ↻ manually or re-enable auto to avoid missing trades.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("ThetaApp")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(kAppVersion)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 1.0, blue: 0.0))
                }

                if let lastUpdate = store.lastUpdated {
                    Text("Updated \(lastUpdate, style: .relative) ago")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                }
            }

            Spacer()

            // Auto-execute toggle — warns before pausing
            Button {
                let isRunning = store.statusMessage?.contains("Auto-execute every") == true
                if isRunning {
                    showPauseWarning = true  // confirm before stopping
                } else {
                    store.startAutoExecution()
                }
            } label: {
                let isRunning = store.statusMessage?.contains("Auto-execute every") == true
                HStack(spacing: 4) {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 10))
                    Text(isRunning ? "AUTO" : "AUTO")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(isRunning ? AppColors.green : AppColors.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((isRunning ? AppColors.green : Color.white).opacity(0.12))
                .clipShape(Capsule())
            }

            // Manual execute
            Button {
                Task { await store.executeWheelCycle() }
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(store.isRefreshing ? .gray : AppColors.gold)
            }
            .disabled(store.isRefreshing)

            // Help button
            Button { showHelp = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.gold)
            }
        }
    }

    // MARK: - Portfolio Cards

    private var portfolioCards: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            // Main NLV card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Net Liquidation")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(DesignTokens.Text.secondary))
                    Text(fmtDollar(store.netLiquidation))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total P&L")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(DesignTokens.Text.secondary))
                    Text(fmtSignedPct(store.totalPnlPct))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(store.totalPnl >= 0 ? AppColors.green : AppColors.red)
                    Text(fmtDollar(store.totalPnl))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(store.totalPnl >= 0 ? AppColors.green : AppColors.red)
                }
            }
            .padding()
            .cardStyle()

            // Stat row
            HStack(spacing: DesignTokens.Spacing.sm) {
                statCard(title: "Cash", value: fmtDollar(store.cash), color: AppColors.gold)
                statCard(title: "Stocks", value: fmtDollar(store.totalStockValue), color: AppColors.blue)
                statCard(title: "Premium", value: fmtDollar(store.totalPremiumCollected), color: AppColors.green)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                statCard(title: "Wheels", value: "\(store.activeWheelCount)", color: AppColors.orange)
                statCard(title: "Positions", value: "\(store.positions.count)", color: AppColors.cyan)
                statCard(title: "Trades", value: "\(store.trades.count)", color: AppColors.purple)
            }
        }
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cardStyle()
    }

    // MARK: - Wheel Status

    private var wheelStatusSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("WHEEL STATUS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(DesignTokens.Text.muted))

            if store.positions.isEmpty {
                emptyState
            } else {
                ForEach(store.positions) { pos in
                    wheelStatusRow(pos)
                }
            }
        }
    }

    private func wheelStatusRow(_ pos: WheelPosition) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // Phase icon
            Image(systemName: pos.phase.icon)
                .foregroundColor(pos.phase.color)
                .font(.system(size: 16))

            // Symbol
            Text(pos.symbol)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            // Phase badge
            Text(pos.phase.shortLabel)
                .pillBadge(color: pos.phase.color)

            Spacer()

            // Price
            VStack(alignment: .trailing, spacing: 2) {
                Text(fmtPrice(pos.currentPrice))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)

                if let opt = pos.currentActiveOption {
                    Text("\(fmtDTE(opt.dte)) · δ\(fmtDelta(opt.contract.delta))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))
                }
            }

            // Collected premium
            Text(fmtDollar(pos.totalPremiumCollected))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(AppColors.green)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .cardStyle()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.2))
            Text("No positions yet")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(DesignTokens.Text.muted))
            Text("Add symbols in the Watchlist tab to start")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(DesignTokens.Text.faint))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Recent Trades

    private var recentTradesSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("RECENT TRADES")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(DesignTokens.Text.muted))

            if store.trades.isEmpty {
                Text("No trades yet")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(store.trades.prefix(10)) { trade in
                    tradeRow(trade)
                }
            }
        }
    }

    private func tradeRow(_ trade: TradeRecord) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            // Action badge
            Text(trade.action.rawValue)
                .pillBadge(color: trade.action.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(trade.symbol)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(trade.note)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(trade.totalAmount >= 0 ? "+\(fmtDollar(trade.totalAmount))" : fmtDollar(trade.totalAmount))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(trade.totalAmount >= 0 ? AppColors.green : AppColors.red)

                Text(trade.date, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(DesignTokens.Text.muted))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .cardStyle()
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        Group {
            if let msg = store.statusMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
