// WheelEngine.swift — The Wheel strategy logic ported from thetagang
// Core decision engine: sell puts → assignment → sell calls → called away → repeat

import Foundation

actor WheelEngine {

    private let config: ThetaConfig
    private let yahoo = YahooFinanceService.shared

    init(config: ThetaConfig) {
        self.config = config
    }

    // MARK: - Main Execution Loop

    /// Run one cycle of the wheel strategy for all positions
    func execute(positions: inout [WheelPosition], cash: inout Double, nlv: Double) async -> [TradeRecord] {
        var trades: [TradeRecord] = []

        // Phase 1: Check existing positions for rolls/closes/expirations
        for i in positions.indices {
            let positionTrades = await checkPosition(&positions[i], cash: &cash, nlv: nlv)
            trades.append(contentsOf: positionTrades)
        }

        // Phase 2: Write new options where needed
        for i in positions.indices {
            if let trade = await writeNewOption(&positions[i], cash: &cash, nlv: nlv) {
                trades.append(trade)
            }
        }

        return trades
    }

    // MARK: - Check Existing Position

    private func checkPosition(_ position: inout WheelPosition, cash: inout Double, nlv: Double) async -> [TradeRecord] {
        var trades: [TradeRecord] = []

        // Update current price
        if let quote = try? await yahoo.fetchQuote(symbol: position.symbol) {
            position.currentPrice = quote.price
        }

        // Check active options
        guard var activeOpt = position.currentActiveOption else { return trades }

        // Update option premium (simplified: use intrinsic + time decay estimate)
        let updatedPremium = estimateCurrentPremium(option: activeOpt, stockPrice: position.currentPrice)
        activeOpt.currentPremium = updatedPremium

        // Update in position
        if let idx = position.activeOptions.firstIndex(where: { $0.id == activeOpt.id }) {
            position.activeOptions[idx].currentPremium = updatedPremium
        }

        // Check expiration
        if activeOpt.dte <= 0 {
            let expirationTrades = handleExpiration(&position, option: activeOpt, cash: &cash)
            trades.append(contentsOf: expirationTrades)
            return trades
        }

        // Check roll eligibility
        if let rollDecision = shouldRoll(option: activeOpt, stockPrice: position.currentPrice) {
            if let rollTrade = await rollPosition(&position, option: activeOpt, reason: rollDecision, cash: &cash, nlv: nlv) {
                trades.append(rollTrade)
            }
        }

        return trades
    }

    // MARK: - Roll Decision (ported from thetagang portfolio_manager.py)

    func shouldRoll(option: ActiveOption, stockPrice: Double) -> RollReason? {
        let pnl = option.pnlPercent

        // Rule 1: P&L target reached (default 90%)
        if pnl >= config.rollPnlTarget {
            return .pnlTarget
        }

        // Rule 2: DTE target reached with minimum P&L
        if option.dte <= config.rollDTE && pnl >= config.rollMinPnl {
            return .dteTarget
        }

        // Rule 3: ITM handling
        let isITM: Bool
        switch option.contract.optionType {
        case .put:
            isITM = stockPrice < option.contract.strike
            if isITM && config.rollPutsITM { return .itm }
        case .call:
            isITM = stockPrice > option.contract.strike
            if isITM && config.rollCallsITM { return .itm }
        }

        return nil
    }

    // MARK: - Roll Execution

    private func rollPosition(_ position: inout WheelPosition, option: ActiveOption,
                              reason: RollReason, cash: inout Double, nlv: Double) async -> TradeRecord? {
        // Close the old option
        let closePremium = option.currentPremium
        closeOption(&position, option: option, action: .roll, premium: closePremium)

        // Cost to close: buy back at current premium
        let closeCost = closePremium * 100.0 * Double(abs(option.quantity))
        cash -= closeCost

        // Find and open new option
        guard let newContract = await findEligibleContract(
            symbol: position.symbol,
            optionType: option.contract.optionType,
            stockPrice: position.currentPrice,
            strikeLimit: calculateStrikeLimit(position: position, optionType: option.contract.optionType)
        ) else { return nil }

        // Check credit-only constraint
        if config.rollCreditOnly && newContract.premium <= closePremium {
            return nil
        }

        // Open new position
        let newOption = ActiveOption(
            contract: newContract,
            quantity: option.quantity,
            openPremium: newContract.premium
        )
        position.activeOptions.append(newOption)

        // Receive new premium
        let newCredit = newContract.premium * 100.0 * Double(abs(option.quantity))
        cash += newCredit
        position.totalPremiumCollected += newCredit

        let netCredit = newCredit - closeCost
        return TradeRecord(
            symbol: position.symbol,
            action: .roll,
            optionType: newContract.optionType,
            strike: newContract.strike,
            expiration: newContract.expiration,
            quantity: option.quantity,
            price: newContract.premium,
            totalAmount: netCredit,
            note: "\(reason.rawValue): \(fmtStrike(option.contract.strike))→\(fmtStrike(newContract.strike)) net \(netCredit >= 0 ? "credit" : "debit") \(fmtPrice(abs(netCredit)))"
        )
    }

    // MARK: - Expiration Handling

    private func handleExpiration(_ position: inout WheelPosition, option: ActiveOption, cash: inout Double) -> [TradeRecord] {
        var trades: [TradeRecord] = []

        let isITM: Bool
        switch option.contract.optionType {
        case .put:
            isITM = position.currentPrice < option.contract.strike
        case .call:
            isITM = position.currentPrice > option.contract.strike
        }

        if isITM {
            // Assignment
            switch option.contract.optionType {
            case .put:
                // Assigned: buy 100 shares at strike price
                let shares = 100 * abs(option.quantity)
                let cost = option.contract.strike * Double(shares)
                position.shares += shares
                position.avgCost = option.contract.strike
                cash -= cost
                position.phase = .assigned

                closeOption(&position, option: option, action: .assignment, premium: 0)

                trades.append(TradeRecord(
                    symbol: position.symbol,
                    action: .assignment,
                    optionType: .put,
                    strike: option.contract.strike,
                    quantity: shares,
                    price: option.contract.strike,
                    totalAmount: -cost,
                    note: "Put assigned: bought \(shares) shares @ \(fmtPrice(option.contract.strike))"
                ))

            case .call:
                // Called away: sell 100 shares at strike price
                let shares = min(position.shares, 100 * abs(option.quantity))
                let proceeds = option.contract.strike * Double(shares)
                position.shares -= shares
                cash += proceeds

                if position.shares <= 0 {
                    position.phase = .calledAway
                    position.wheelCycleCount += 1
                    position.avgCost = 0
                }

                closeOption(&position, option: option, action: .calledAway, premium: 0)

                trades.append(TradeRecord(
                    symbol: position.symbol,
                    action: .calledAway,
                    optionType: .call,
                    strike: option.contract.strike,
                    quantity: shares,
                    price: option.contract.strike,
                    totalAmount: proceeds,
                    note: "Called away: sold \(shares) shares @ \(fmtPrice(option.contract.strike))"
                ))
            }
        } else {
            // Expired worthless — keep the premium
            closeOption(&position, option: option, action: .expired, premium: 0)

            trades.append(TradeRecord(
                symbol: position.symbol,
                action: .expired,
                optionType: option.contract.optionType,
                strike: option.contract.strike,
                expiration: option.contract.expiration,
                quantity: abs(option.quantity),
                price: 0,
                totalAmount: 0,
                note: "Expired worthless — premium kept"
            ))
        }

        return trades
    }

    // MARK: - Write New Options

    private func writeNewOption(_ position: inout WheelPosition, cash: inout Double, nlv: Double) async -> TradeRecord? {
        // Skip if already has an active option
        if position.currentActiveOption != nil { return nil }

        // Determine what to write based on phase
        let optionType: OptionType
        switch position.phase {
        case .idle, .calledAway:
            optionType = .put
            position.phase = .sellingPuts
        case .assigned:
            optionType = .call
            position.phase = .sellingCalls
        case .sellingPuts:
            optionType = .put   // already in put phase, proceed to write
        case .sellingCalls:
            optionType = .call  // already in call phase, proceed to write
        }

        // Check write threshold
        if config.writeThreshold > 0 {
            if let quote = try? await yahoo.fetchQuote(symbol: position.symbol) {
                if abs(quote.dailyChangePct) < config.writeThreshold {
                    return nil  // Not enough movement
                }
            }
        }

        // Find eligible contract
        guard let contract = await findEligibleContract(
            symbol: position.symbol,
            optionType: optionType,
            stockPrice: position.currentPrice,
            strikeLimit: calculateStrikeLimit(position: position, optionType: optionType)
        ) else { return nil }

        // Check minimum credit
        guard config.meetsMinimumCredit(contract.premium) else { return nil }

        // Calculate quantity
        let quantity = calculateQuantity(
            position: position,
            optionType: optionType,
            stockPrice: position.currentPrice,
            nlv: nlv,
            cash: cash
        )
        guard quantity > 0 else { return nil }

        // Execute: sell to open
        let newOption = ActiveOption(
            contract: contract,
            quantity: -quantity,  // negative = short
            openPremium: contract.premium
        )
        position.activeOptions.append(newOption)

        let credit = contract.premium * 100.0 * Double(quantity)
        cash += credit
        position.totalPremiumCollected += credit

        return TradeRecord(
            symbol: position.symbol,
            action: .sellToOpen,
            optionType: optionType,
            strike: contract.strike,
            expiration: contract.expiration,
            quantity: -quantity,
            price: contract.premium,
            totalAmount: credit,
            note: "STO \(quantity) \(contract.displayLabel) @ \(fmtPrice(contract.premium))"
        )
    }

    // MARK: - Find Eligible Contract (ported from thetagang)

    func findEligibleContract(symbol: String, optionType: OptionType,
                              stockPrice: Double, strikeLimit: Double?) async -> OptionContract? {
        guard let chain = try? await yahoo.fetchOptionChain(symbol: symbol) else { return nil }

        // Find expiration closest to target DTE
        let targetDate = Calendar.current.date(byAdding: .day, value: config.targetDTE, to: Date())!
        let targetDTE = config.targetDTE

        // Get all expirations and find best match
        let sortedExps = chain.expirations.sorted()
        guard let bestExp = sortedExps.min(by: {
            abs(Calendar.current.dateComponents([.day], from: Date(), to: $0).day! - targetDTE)
            < abs(Calendar.current.dateComponents([.day], from: Date(), to: $1).day! - targetDTE)
        }) else { return nil }

        // Fetch chain for that expiration
        guard let expChain = try? await yahoo.fetchOptionChain(symbol: symbol, expiration: bestExp) else { return nil }

        let quotes = optionType == .put ? expChain.puts : expChain.calls

        // Filter by open interest and strike limit
        let filtered = quotes.filter { q in
            q.openInterest >= config.minOpenInterest &&
            q.midpoint > 0 &&
            (strikeLimit == nil || (optionType == .put ? q.strike <= strikeLimit! : q.strike >= strikeLimit!))
        }

        // Find contract closest to target delta
        let target = config.targetDelta
        guard let best = filtered.min(by: {
            abs($0.delta - target) < abs($1.delta - target)
        }) else {
            // Fallback: pick OTM strike closest to target delta distance from current price
            return selectByStrikeDistance(quotes: quotes, stockPrice: stockPrice,
                                         optionType: optionType, expiration: bestExp, symbol: symbol)
        }

        return OptionContract(
            symbol: symbol,
            optionType: optionType,
            strike: best.strike,
            expiration: best.expiration,
            delta: best.delta,
            premium: best.midpoint,
            openInterest: best.openInterest,
            impliedVol: best.impliedVol
        )
    }

    /// Fallback: select strike by distance from stock price (approximating delta)
    private func selectByStrikeDistance(quotes: [OptionQuote], stockPrice: Double,
                                       optionType: OptionType, expiration: Date, symbol: String) -> OptionContract? {
        // Target ~0.30 delta ≈ roughly 1 standard deviation OTM
        // Approximate: strike about 5-8% OTM for 45 DTE
        let otmFactor = optionType == .put ? (1.0 - config.targetDelta * 0.3) : (1.0 + config.targetDelta * 0.3)
        let targetStrike = stockPrice * otmFactor

        let otm = quotes.filter { q in
            q.midpoint > 0 &&
            (optionType == .put ? q.strike < stockPrice : q.strike > stockPrice)
        }

        guard let best = otm.min(by: {
            abs($0.strike - targetStrike) < abs($1.strike - targetStrike)
        }) else { return nil }

        return OptionContract(
            symbol: symbol,
            optionType: optionType,
            strike: best.strike,
            expiration: expiration,
            delta: best.delta,
            premium: best.midpoint,
            openInterest: best.openInterest,
            impliedVol: best.impliedVol
        )
    }

    // MARK: - Calculate Quantity

    private func calculateQuantity(position: WheelPosition, optionType: OptionType,
                                   stockPrice: Double, nlv: Double, cash: Double) -> Int {
        switch optionType {
        case .put:
            // Number of puts = target shares / 100
            let targetValue = position.weight * config.buyingPower(nlv: nlv)
            let targetShares = Int(targetValue / stockPrice)
            let targetContracts = max(1, targetShares / 100)

            // Cap by max new contracts percent
            let maxValue = config.maxNewContractValue(nlv: nlv)
            let maxContracts = max(1, Int(maxValue / (stockPrice * 100)))

            // Cap by available cash (need to cover assignment)
            let cashContracts = Int(cash / (stockPrice * 100))

            return min(targetContracts, min(maxContracts, cashContracts))

        case .call:
            // Number of calls = shares owned / 100, capped by callCapFactor
            let maxCalls = Int(Double(position.shares) / 100.0 * config.callCapFactor)
            return max(0, maxCalls)
        }
    }

    // MARK: - Strike Limit Calculation

    private func calculateStrikeLimit(position: WheelPosition, optionType: OptionType) -> Double? {
        switch optionType {
        case .put:
            // Don't sell puts above current price (stay OTM)
            return position.currentPrice
        case .call:
            // Don't sell calls below cost basis (protect from selling at a loss)
            if config.maintainHighWaterMark && position.avgCost > 0 {
                return position.avgCost
            }
            return position.currentPrice
        }
    }

    // MARK: - Premium Estimation

    /// Estimate current premium based on time decay and stock movement
    func estimateCurrentPremium(option: ActiveOption, stockPrice: Double) -> Double {
        let contract = option.contract
        let dte = max(1, contract.dte)
        let originalDTE = max(1, Calendar.current.dateComponents(
            [.day], from: option.openDate, to: contract.expiration
        ).day ?? 45)

        // Time decay factor (theta decay is roughly sqrt of time ratio)
        let timeRatio = Double(dte) / Double(originalDTE)
        let timeFactor = sqrt(timeRatio)

        // Intrinsic value
        let intrinsic: Double
        switch contract.optionType {
        case .put:
            intrinsic = max(0, contract.strike - stockPrice)
        case .call:
            intrinsic = max(0, stockPrice - contract.strike)
        }

        // Extrinsic = original premium * time decay factor
        let originalExtrinsic = max(0, option.openPremium - max(0, contract.optionType == .put
            ? contract.strike - stockPrice : stockPrice - contract.strike))
        let currentExtrinsic = originalExtrinsic * timeFactor

        return intrinsic + currentExtrinsic
    }

    // MARK: - Volatility Calculation (for write threshold sigma)

    func calculateDailyStdDev(symbol: String) async -> Double? {
        guard let prices = try? await yahoo.fetchHistory(symbol: symbol, days: config.dailyStddevWindow + 10) else {
            return nil
        }
        guard prices.count >= 2 else { return nil }

        // Calculate log returns
        var logReturns: [Double] = []
        for i in 1..<prices.count {
            if prices[i] > 0 && prices[i-1] > 0 {
                logReturns.append(log(prices[i] / prices[i-1]))
            }
        }

        guard logReturns.count >= 2 else { return nil }

        let mean = logReturns.reduce(0, +) / Double(logReturns.count)
        let variance = logReturns.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(logReturns.count - 1)
        return sqrt(variance)
    }

    // MARK: - Helpers

    private func closeOption(_ position: inout WheelPosition, option: ActiveOption,
                             action: TradeAction, premium: Double) {
        if let idx = position.activeOptions.firstIndex(where: { $0.id == option.id }) {
            position.activeOptions[idx].isClosed = true
            position.activeOptions[idx].closeDate = Date()
            position.activeOptions[idx].closePremium = premium
            position.activeOptions[idx].closeAction = action
        }
    }
}
