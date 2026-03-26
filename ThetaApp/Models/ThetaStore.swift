// ThetaStore.swift — Main state store for ThetaApp
// Manages positions, cash, trades, and auto-execution timer

import SwiftUI
import Combine

@MainActor
class ThetaStore: ObservableObject {

    // MARK: - Published State

    @Published var positions: [WheelPosition] = []
    @Published var cash: Double = 100_000
    @Published var trades: [TradeRecord] = []
    @Published var snapshots: [PortfolioSnapshot] = []
    @Published var isRefreshing = false
    @Published var lastUpdated: Date?
    @Published var statusMessage: String?

    // MARK: - Config

    let config: ThetaConfig

    // MARK: - Engine

    private var engine: WheelEngine
    private var timer: AnyCancellable?

    // MARK: - Computed

    var netLiquidation: Double {
        let stockValue = positions.reduce(0.0) { $0 + $1.marketValue }
        let optionValue = positions.reduce(0.0) { $0 + $1.openOptionPnl }
        return cash + stockValue + optionValue
    }

    var totalStockValue: Double {
        positions.reduce(0.0) { $0 + $1.marketValue }
    }

    var totalPremiumCollected: Double {
        positions.reduce(0.0) { $0 + $1.totalPremiumCollected }
    }

    var totalUnrealizedPnl: Double {
        positions.reduce(0.0) { $0 + $1.unrealizedPnl }
    }

    var totalPnl: Double {
        netLiquidation - config.startingCash
    }

    var totalPnlPct: Double {
        config.startingCash > 0 ? totalPnl / config.startingCash : 0
    }

    var activeWheelCount: Int {
        positions.filter { $0.phase != .idle }.count
    }

    // MARK: - Init

    init(config: ThetaConfig) {
        self.config = config
        self.engine = WheelEngine(config: config)
        self.cash = config.startingCash
        loadState()
    }

    // MARK: - Auto Execution Timer

    func startAutoExecution() {
        stopAutoExecution()
        let interval = TimeInterval(config.refreshInterval * 60)
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.executeWheelCycle() }
            }
        statusMessage = "Auto-execute every \(config.refreshInterval)m"
    }

    func stopAutoExecution() {
        timer?.cancel()
        timer = nil
        statusMessage = "Auto-execute stopped"
    }

    // MARK: - Manual Refresh

    func refreshPrices() async {
        isRefreshing = true
        defer {
            isRefreshing = false
            lastUpdated = Date()
        }

        await withTaskGroup(of: (Int, Double?).self) { group in
            for (index, position) in positions.enumerated() {
                group.addTask {
                    let quote = try? await YahooFinanceService.shared.fetchQuote(symbol: position.symbol)
                    return (index, quote?.price)
                }
            }

            for await (index, price) in group {
                if let price, index < positions.count {
                    positions[index].currentPrice = price
                }
            }
        }
    }

    // MARK: - Execute Wheel Cycle

    func executeWheelCycle() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastUpdated = Date()
        }

        statusMessage = "Executing wheel cycle..."

        var mutablePositions = positions
        var mutableCash = cash

        let newTrades = await engine.execute(
            positions: &mutablePositions,
            cash: &mutableCash,
            nlv: netLiquidation
        )

        positions = mutablePositions
        cash = mutableCash
        trades.insert(contentsOf: newTrades, at: 0)

        // Take snapshot
        let snapshot = PortfolioSnapshot(
            nlv: netLiquidation,
            cash: cash,
            stockValue: totalStockValue,
            optionValue: positions.reduce(0.0) { $0 + $1.openOptionPnl },
            totalPremium: totalPremiumCollected
        )
        snapshots.append(snapshot)

        if newTrades.isEmpty {
            statusMessage = "No trades this cycle"
        } else {
            statusMessage = "\(newTrades.count) trade(s) executed"
        }

        saveState()
    }

    // MARK: - Symbol Management

    func addSymbol(_ symbol: String, weight: Double) {
        guard !positions.contains(where: { $0.symbol.uppercased() == symbol.uppercased() }) else { return }
        var position = WheelPosition(symbol: symbol.uppercased(), weight: weight)

        // Fetch initial price
        Task {
            if let quote = try? await YahooFinanceService.shared.fetchQuote(symbol: symbol.uppercased()) {
                if let idx = positions.firstIndex(where: { $0.symbol == symbol.uppercased() }) {
                    positions[idx].currentPrice = quote.price
                }
            }
        }

        positions.append(position)
        rebalanceWeights()
        saveState()
    }

    func removeSymbol(_ symbol: String) {
        positions.removeAll { $0.symbol == symbol }
        rebalanceWeights()
        saveState()
    }

    func updateWeight(symbol: String, weight: Double) {
        if let idx = positions.firstIndex(where: { $0.symbol == symbol }) {
            positions[idx].weight = weight
        }
        saveState()
    }

    /// Auto-rebalance weights to sum to 1.0
    private func rebalanceWeights() {
        guard !positions.isEmpty else { return }
        let totalWeight = positions.reduce(0.0) { $0 + $1.weight }
        if totalWeight > 0 {
            for i in positions.indices {
                positions[i].weight = positions[i].weight / totalWeight
            }
        } else {
            let equalWeight = 1.0 / Double(positions.count)
            for i in positions.indices {
                positions[i].weight = equalWeight
            }
        }
    }

    // MARK: - Reset

    func resetSimulation() {
        positions.removeAll()
        trades.removeAll()
        snapshots.removeAll()
        cash = config.startingCash
        lastUpdated = nil
        statusMessage = "Simulation reset"
        saveState()
    }

    // MARK: - Persistence

    private let positionsKey = "theta_positions"
    private let tradesKey = "theta_trades"
    private let snapshotsKey = "theta_snapshots"
    private let cashKey = "theta_cash"

    func saveState() {
        if let data = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(data, forKey: positionsKey)
        }
        if let data = try? JSONEncoder().encode(trades) {
            UserDefaults.standard.set(data, forKey: tradesKey)
        }
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: snapshotsKey)
        }
        UserDefaults.standard.set(cash, forKey: cashKey)
    }

    func loadState() {
        if let data = UserDefaults.standard.data(forKey: positionsKey),
           let decoded = try? JSONDecoder().decode([WheelPosition].self, from: data) {
            positions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: tradesKey),
           let decoded = try? JSONDecoder().decode([TradeRecord].self, from: data) {
            trades = decoded
        }
        if let data = UserDefaults.standard.data(forKey: snapshotsKey),
           let decoded = try? JSONDecoder().decode([PortfolioSnapshot].self, from: data) {
            snapshots = decoded
        }
        let savedCash = UserDefaults.standard.double(forKey: cashKey)
        if savedCash > 0 { cash = savedCash }
    }
}
