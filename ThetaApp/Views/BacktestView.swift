// BacktestView.swift — Historical backtest UI
// Run wheel strategy simulations on past data

import SwiftUI
import Charts

struct BacktestView: View {
    @EnvironmentObject var config: ThetaConfig
    @State private var showHelp = false

    // Input
    @State private var symbol = "AAPL"
    @State private var months = 12
    @State private var isRunning = false
    @State private var errorMessage: String?

    // Results
    @State private var result: BacktestResult?
    @State private var selectedTab: BacktestTab = .summary

    enum BacktestTab: String, CaseIterable {
        case summary = "Summary"
        case chart   = "Chart"
        case trades  = "Trades"
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                headerBar
                inputSection

                if isRunning {
                    runningView
                } else if let result {
                    resultTabs(result)
                } else {
                    emptyState
                }
            }
        }
        .sheet(isPresented: $showHelp) { HelpSheet(screen: .backtest) }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Backtest")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            Button { showHelp = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.gold)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(spacing: 4) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                // Symbol
                VStack(alignment: .leading, spacing: 2) {
                    Text("SYMBOL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    TextField("AAPL", text: $symbol)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }

                // Period
                VStack(alignment: .leading, spacing: 2) {
                    Text("PERIOD")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    Picker("", selection: $months) {
                        Text("6mo").tag(6)
                        Text("1yr").tag(12)
                        Text("2yr").tag(24)
                        Text("3yr").tag(36)
                    }
                    .pickerStyle(.segmented)
                }

                // Run button
                Button {
                    Task { await runBacktest() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("RUN")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppColors.green)
                    .clipShape(Capsule())
                }
                .disabled(isRunning || symbol.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.red)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .tint(AppColors.gold)
            Text("Running backtest for \(symbol)...")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(DesignTokens.Text.secondary))
            Text("Fetching \(months) months of data & simulating wheel")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(DesignTokens.Text.muted))
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.15))
            Text("Historical Backtest")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(DesignTokens.Text.muted))
            Text("Enter a symbol and period to see how\nThe Wheel would have performed")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(DesignTokens.Text.faint))
                .multilineTextAlignment(.center)

            // Quick-launch chips
            HStack(spacing: 8) {
                ForEach(["AAPL", "NVDA", "SPY", "MU", "AMD"], id: \.self) { sym in
                    Button {
                        symbol = sym
                        Task { await runBacktest() }
                    } label: {
                        Text(sym)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AppColors.gold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.gold.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Result Tabs

    private func resultTabs(_ result: BacktestResult) -> some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(BacktestTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)

            // Tab content
            switch selectedTab {
            case .summary: summaryTab(result)
            case .chart:   chartTab(result)
            case .trades:  tradesTab(result)
            }
        }
    }

    // MARK: - Summary Tab

    private func summaryTab(_ r: BacktestResult) -> some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.sm) {
                // Main result card
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(r.symbol) Wheel Backtest")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text(dateRange(r.startDate, r.endDate))
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(r.totalReturnPct)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundColor(r.totalReturn >= 0 ? AppColors.green : AppColors.red)
                        Text("total return")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    }
                }
                .padding()
                .cardStyle()

                // Metrics grid
                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                ], spacing: DesignTokens.Spacing.sm) {
                    metricCard("Final NLV", fmtDollar(r.finalNLV), AppColors.gold)
                    metricCard("Annualized", r.annualizedPct, r.annualizedReturn >= 0 ? AppColors.green : AppColors.red)
                    metricCard("Premium", fmtDollar(r.totalPremium), AppColors.green)
                    metricCard("Max Drawdown", r.maxDrawdownPct, AppColors.red)
                    metricCard("Sharpe", String(format: "%.2f", r.sharpeRatio), r.sharpeRatio >= 1 ? AppColors.green : AppColors.yellow)
                    metricCard("Win Rate", r.winRatePct, r.winRate >= 0.6 ? AppColors.green : AppColors.yellow)
                    metricCard("Trades", "\(r.totalTrades)", AppColors.cyan)
                    metricCard("Cycles", "\(r.wheelCycles)", AppColors.orange)
                    metricCard("Avg Days", String(format: "%.0f", r.avgDaysInTrade), AppColors.blue)
                }

                // Config used
                VStack(alignment: .leading, spacing: 4) {
                    Text("SETTINGS USED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    HStack(spacing: 16) {
                        configLabel("Cash", fmtDollar(r.startingCash))
                        configLabel("Delta", fmtDelta(config.targetDelta))
                        configLabel("DTE", "\(config.targetDTE)d")
                        configLabel("Roll", fmtPct(config.rollPnlTarget))
                    }
                }
                .padding()
                .cardStyle()
            }
            .padding()
        }
    }

    private func metricCard(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cardStyle()
    }

    private func configLabel(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(DesignTokens.Text.muted))
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(AppColors.gold)
        }
    }

    // MARK: - Chart Tab

    private func chartTab(_ r: BacktestResult) -> some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                // Equity curve
                VStack(alignment: .leading, spacing: 6) {
                    Text("EQUITY CURVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))

                    if #available(iOS 17.0, *) {
                        Chart(r.dailySnapshots) { snap in
                            LineMark(
                                x: .value("Date", snap.date),
                                y: .value("NLV", snap.nlv)
                            )
                            .foregroundStyle(AppColors.gold)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))

                            AreaMark(
                                x: .value("Date", snap.date),
                                yStart: .value("Base", r.startingCash),
                                yEnd: .value("NLV", snap.nlv)
                            )
                            .foregroundStyle(
                                snap.nlv >= r.startingCash
                                    ? AppColors.green.opacity(0.1)
                                    : AppColors.red.opacity(0.1)
                            )
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text(fmtDollar(v))
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                }
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                    .foregroundStyle(Color.white.opacity(0.08))
                            }
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisValueLabel {
                                    if let d = value.as(Date.self) {
                                        Text(shortDate(d))
                                            .font(.system(size: 8))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                }
                            }
                        }
                        .frame(height: 220)
                        .padding()
                        .cardStyle()
                    }
                }

                // Premium accumulation
                VStack(alignment: .leading, spacing: 6) {
                    Text("CUMULATIVE PREMIUM")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))

                    if #available(iOS 17.0, *) {
                        Chart(r.dailySnapshots) { snap in
                            AreaMark(
                                x: .value("Date", snap.date),
                                y: .value("Premium", snap.cumulativePremium)
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [AppColors.green.opacity(0.3), AppColors.green.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Date", snap.date),
                                y: .value("Premium", snap.cumulativePremium)
                            )
                            .foregroundStyle(AppColors.green)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text(fmtDollar(v))
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisValueLabel {
                                    if let d = value.as(Date.self) {
                                        Text(shortDate(d))
                                            .font(.system(size: 8))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                }
                            }
                        }
                        .frame(height: 160)
                        .padding()
                        .cardStyle()
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Trades Tab

    private func tradesTab(_ r: BacktestResult) -> some View {
        List {
            ForEach(r.trades.reversed()) { trade in
                HStack(spacing: DesignTokens.Spacing.sm) {
                    // Action badge
                    Text(trade.action)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(tradeColor(trade.action))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(tradeColor(trade.action).opacity(0.15))
                        .clipShape(Capsule())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(fmtPrice(trade.strike))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                        Text(trade.note)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        if trade.pnl != 0 {
                            Text(trade.pnl >= 0 ? "+\(fmtDollar(trade.pnl))" : fmtDollar(trade.pnl))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(trade.pnl >= 0 ? AppColors.green : AppColors.red)
                        }
                        Text(shortDate(trade.date))
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    }
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func tradeColor(_ action: String) -> Color {
        switch action {
        case "STO PUT":  return AppColors.orange
        case "STO CALL": return AppColors.green
        case "ROLL":     return AppColors.yellow
        case "ASSIGNED": return AppColors.red
        case "CALLED":   return AppColors.blue
        case "EXPIRED":  return AppColors.green
        default:         return AppColors.muted
        }
    }

    // MARK: - Run Backtest

    private func runBacktest() async {
        let sym = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !sym.isEmpty else { return }
        symbol = sym

        isRunning = true
        errorMessage = nil
        result = nil

        let btConfig = BacktestConfig.from(config: config, symbol: sym, months: months)
        let engine = BacktestEngine()

        do {
            result = try await engine.run(config: btConfig)
            selectedTab = .summary
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    // MARK: - Helpers

    private func dateRange(_ start: Date, _ end: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM yyyy"
        return "\(df.string(from: start)) – \(df.string(from: end))"
    }

    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "M/d/yy"
        return df.string(from: date)
    }
}
