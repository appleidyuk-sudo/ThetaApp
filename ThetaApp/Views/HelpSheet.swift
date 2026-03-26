// HelpSheet.swift — Context-sensitive help for each screen

import SwiftUI

enum HelpScreen {
    case dashboard
    case positions
    case settings
}

struct HelpSheet: View {
    let screen: HelpScreen
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                        switch screen {
                        case .dashboard:  dashboardHelp
                        case .positions:  positionsHelp
                        case .settings:   settingsHelp
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppColors.gold)
                }
            }
        }
    }

    private var title: String {
        switch screen {
        case .dashboard: return "Dashboard Help"
        case .positions: return "Positions Help"
        case .settings:  return "Settings Help"
        }
    }

    // MARK: - Dashboard Help

    private var dashboardHelp: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            helpSection("The Wheel Strategy", items: [
                "Sell cash-secured puts (CSP) on stocks you want to own",
                "If assigned, sell covered calls (CC) on your shares",
                "If called away, start over — collect premium each step",
                "Repeat the cycle to generate income from theta decay",
            ])

            helpSection("Net Liquidation (NLV)", items: [
                "Total portfolio value: cash + stock holdings + option P&L",
                "This is your account's true worth at any moment",
            ])

            helpSection("Total P&L", items: [
                "Gain or loss vs. your starting cash amount",
                "Shown as both dollar amount and percentage",
                "Green = profit, Red = loss",
            ])

            helpSection("Stat Cards", items: [
                "Cash — available cash not tied up in positions",
                "Stocks — market value of shares you own (from assignments)",
                "Premium — total option premium collected across all trades",
                "Wheels — number of active wheel cycles running",
                "Positions — total symbols in your watchlist",
                "Trades — total number of executed trades",
            ])

            helpSection("Wheel Status", items: [
                "CSP (orange) — selling cash-secured puts, waiting for assignment",
                "OWN (yellow) — assigned shares, looking to sell covered calls",
                "CC (green) — selling covered calls on owned shares",
                "DONE (blue) — shares called away, cycle complete",
                "IDLE (gray) — no active option, next cycle will write one",
                "δ = delta of active option, DTE = days to expiration",
            ])

            helpSection("Controls", items: [
                "▶ Play/Pause — toggle auto-execution timer",
                "↻ Refresh — manually run one wheel cycle now",
                "Pull down to refresh prices without executing trades",
            ])

            helpSection("Recent Trades", items: [
                "STO — Sell To Open: opened a new short option",
                "BTC — Buy To Close: closed an option position",
                "ROLL — closed old option, opened new one at better strike/date",
                "ASSIGN — put expired ITM, bought 100 shares at strike",
                "CALLED — call expired ITM, sold 100 shares at strike",
                "EXPIRED — option expired worthless, premium kept",
            ])
        }
    }

    // MARK: - Positions Help

    private var positionsHelp: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            helpSection("Position List", items: [
                "Each row shows one symbol in your wheel portfolio",
                "Tap a row to see full details, trade history, and roll status",
                "Swipe left to remove a position",
                "Tap + to add a new symbol",
            ])

            helpSection("Row Layout", items: [
                "Left icon — color-coded wheel phase indicator",
                "Symbol — ticker in monospaced font",
                "Phase badge — CSP / OWN / CC / DONE / IDLE",
                "Shares — number of shares owned (if assigned)",
                "Weight — portfolio allocation percentage",
            ])

            helpSection("Active Option Info", items: [
                "Contract label — expiration date, type (P/C), strike price",
                "Green = call, Red = put",
                "δ (delta) — probability of finishing ITM (target: 0.30)",
                "DTE — days to expiration (red when ≤15, yellow otherwise)",
            ])

            helpSection("P&L Column", items: [
                "Current price — latest stock price from Yahoo",
                "Dollar P&L — unrealized gain/loss on active option",
                "Percent P&L — gain as % of premium received",
                "Green = winning, Red = losing",
            ])

            helpSection("Premium Column", items: [
                "Total premium collected on this symbol across all trades",
                "×N — number of completed wheel cycles",
            ])

            helpSection("Sort Headers", items: [
                "Tap SYMBOL, PHASE, DTE, or P&L to sort",
                "Tap again to reverse sort direction",
            ])

            helpSection("High IV Suggestions", items: [
                "Shown when adding a new symbol via the + button",
                "Scans popular wheel candidates for implied volatility",
                "IV % — annualized implied vol from ATM puts",
                "Yield — annualized premium as % of stock price",
                "~30d — estimated 30-day ATM put premium in dollars",
                "Higher IV = more premium but more risk",
                "Tap a suggestion to auto-fill the symbol field",
            ])
        }
    }

    // MARK: - Settings Help

    private var settingsHelp: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            helpSection("Account", items: [
                "Starting Cash — initial simulated capital",
                "Margin Usage — fraction of NLV available as buying power (1.0 = full)",
            ])

            helpSection("Target", items: [
                "Target Delta — option delta to sell at (0.30 = ~70% OTM probability)",
                "Target DTE — ideal days to expiration (45d captures peak theta decay)",
                "Max DTE — won't sell options beyond this expiration",
                "Min Open Interest — skip illiquid contracts below this OI",
                "Min Credit — minimum premium per share to accept a trade",
            ])

            helpSection("Roll When", items: [
                "P&L Target — roll when profit reaches this % of max (90% = close winner early)",
                "DTE Trigger — roll when days left falls to this (15d = avoid gamma risk)",
                "Min P&L for DTE Roll — minimum profit % to allow a DTE-triggered roll",
                "Roll Puts/Calls ITM — auto-roll when option goes in-the-money",
                "Credit Only — only roll if new option gives a net credit",
                "High Water Mark — don't sell calls below cost basis",
            ])

            helpSection("Write When", items: [
                "Puts on Red Days — only sell puts when stock is down today",
                "Calls on Green Days — only sell calls when stock is up today",
                "Call Cap Factor — fraction of shares to cover (1.0 = all shares)",
                "Max New Contracts % — max new position size as % of NLV",
            ])

            helpSection("Write Threshold", items: [
                "Price Change Threshold — min daily move to trigger a new write (0 = disabled)",
                "Sigma Threshold — min move in std deviations to write",
                "Std Dev Window — lookback days for calculating daily volatility",
            ])

            helpSection("VIX Hedging", items: [
                "Buy VIX calls as portfolio insurance when enabled",
                "VIX Hedge Delta/DTE — targeting parameters for VIX calls",
                "VIX Allocation — % of NLV to spend on VIX protection",
                "Close Above — close VIX hedge when VIX exceeds this level",
            ])

            helpSection("Cash Management", items: [
                "Park idle cash in a money market ETF (default: SGOV)",
                "Buy Threshold — buy fund when cash exceeds this % of NLV",
                "Sell Threshold — sell fund when cash drops below this %",
            ])

            helpSection("Regime Rebalance", items: [
                "Adjust position weights based on market regime (bull/bear)",
                "Lookback Days — window for trend detection",
                "Soft/Hard Band — tolerance before rebalancing triggers",
            ])

            helpSection("Execution", items: [
                "Refresh Interval — minutes between auto-execution cycles",
                "Auto Execute — enable/disable the automatic wheel timer",
            ])
        }
    }

    // MARK: - Help Section Builder

    private func helpSection(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppColors.gold)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.gold.opacity(0.6))
                    Text(item)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(DesignTokens.Text.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .cardStyle()
    }
}
