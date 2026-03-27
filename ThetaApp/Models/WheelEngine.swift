// WheelEngine.swift — The Wheel strategy logic ported from thetagang
// Core decision engine: sell puts → assignment → sell calls → called away → repeat

import Foundation

actor WheelEngine {

    private let config: ThetaConfig
    private let yahoo = YahooFinanceService.shared

    /// Diagnostic log — published via ThetaStore.statusMessage
    var lastDiagnostic: String = ""

    init(config: ThetaConfig) {
        self.config = config
    }

    private func log(_ msg: String) {
        lastDiagnostic = msg
        print("[WheelEngine] \(msg)")
    }

    // MARK: - Main Execution Loop

    /// Run one cycle of the wheel strategy for all positions
    func execute(positions: inout [WheelPosition], cash: inout Double, nlv: Double) async -> [TradeRecord] {
        var trades: [TradeRecord] = []
        log("Executing for \(positions.count) positions, cash=\(fmtDollar(cash)), nlv=\(fmtDollar(nlv))")

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

        log("Cycle done: \(trades.count) trades")
        return trades
    }

    // MARK: - Check Existing Position

    private func checkPosition(_ position: inout WheelPosition, cash: inout Double, nlv: Double) async -> [TradeRecord] {
        var trades: [TradeRecord] = []

        // Update current price
        do {
            let quote = try await yahoo.fetchQuote(symbol: position.symbol)
            position.currentPrice = quote.price
            log("\(position.symbol) price=\(fmtPrice(quote.price))")
        } catch {
            log("\(position.symbol) price fetch failed: \(error.localizedDescription)")
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
        switch option.contract.optionType {
        case .put:
            let isITM = stockPrice < option.contract.strike
            if isITM && config.rollPutsITM { return .itm }
        case .call:
            let isITM = stockPrice > option.contract.strike
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
        guard let newContract = await findOrSynthesizeContract(
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
            switch option.contract.optionType {
            case .put:
                let shares = 100 * abs(option.quantity)
                let cost = option.contract.strike * Double(shares)
                position.shares += shares
                position.avgCost = option.contract.strike
                cash -= cost
                position.phase = .assigned

                closeOption(&position, option: option, action: .assignment, premium: 0)
                trades.append(TradeRecord(
                    symbol: position.symbol, action: .assignment, optionType: .put,
                    strike: option.contract.strike, quantity: shares,
                    price: option.contract.strike, totalAmount: -cost,
                    note: "Put assigned: bought \(shares) shares @ \(fmtPrice(option.contract.strike))"
                ))

            case .call:
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
                    symbol: position.symbol, action: .calledAway, optionType: .call,
                    strike: option.contract.strike, quantity: shares,
                    price: option.contract.strike, totalAmount: proceeds,
                    note: "Called away: sold \(shares) shares @ \(fmtPrice(option.contract.strike))"
                ))
            }
        } else {
            closeOption(&position, option: option, action: .expired, premium: 0)
            trades.append(TradeRecord(
                symbol: position.symbol, action: .expired,
                optionType: option.contract.optionType,
                strike: option.contract.strike, expiration: option.contract.expiration,
                quantity: abs(option.quantity), price: 0, totalAmount: 0,
                note: "Expired worthless — premium kept"
            ))
        }

        return trades
    }

    // MARK: - Write New Options

    private func writeNewOption(_ position: inout WheelPosition, cash: inout Double, nlv: Double) async -> TradeRecord? {
        // Skip if already has an active option
        if position.currentActiveOption != nil {
            log("\(position.symbol) skip: already has active option")
            return nil
        }

        // Need a valid price
        if position.currentPrice <= 0 {
            log("\(position.symbol) skip: price is \(position.currentPrice)")
            return nil
        }

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
            optionType = .put
        case .sellingCalls:
            optionType = .call
        }

        log("\(position.symbol) phase=\(position.phase.rawValue) writing \(optionType.rawValue) price=\(fmtPrice(position.currentPrice))")

        // Check write threshold
        if config.writeThreshold > 0 {
            if let quote = try? await yahoo.fetchQuote(symbol: position.symbol) {
                if abs(quote.dailyChangePct) < config.writeThreshold {
                    log("\(position.symbol) skip: daily change \(fmtPct(quote.dailyChangePct)) below threshold \(fmtPct(config.writeThreshold))")
                    return nil
                }
            }
        }

        // Find eligible contract (tries Yahoo chain first, falls back to synthetic)
        guard let contract = await findOrSynthesizeContract(
            symbol: position.symbol,
            optionType: optionType,
            stockPrice: position.currentPrice,
            strikeLimit: calculateStrikeLimit(position: position, optionType: optionType)
        ) else {
            log("\(position.symbol) FAILED: could not find or synthesize contract")
            return nil
        }

        log("\(position.symbol) found contract: \(contract.displayLabel) premium=\(fmtPrice(contract.premium)) delta=\(fmtDelta(contract.delta))")

        // Check minimum credit
        guard config.meetsMinimumCredit(contract.premium) else {
            log("\(position.symbol) skip: premium \(fmtPrice(contract.premium)) below min \(fmtPrice(config.minimumCredit))")
            return nil
        }

        // Calculate quantity
        let quantity = calculateQuantity(
            position: position,
            optionType: optionType,
            stockPrice: position.currentPrice,
            nlv: nlv,
            cash: cash
        )
        guard quantity > 0 else {
            log("\(position.symbol) skip: quantity=0 (cash=\(fmtDollar(cash)), price=\(fmtPrice(position.currentPrice)))")
            return nil
        }

        log("\(position.symbol) STO \(quantity) contracts")

        // Execute: sell to open
        let newOption = ActiveOption(
            contract: contract,
            quantity: -quantity,
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

    // MARK: - Find or Synthesize Contract

    /// Try Yahoo option chain first; if it fails, generate a synthetic contract via Black-Scholes
    private func findOrSynthesizeContract(symbol: String, optionType: OptionType,
                                          stockPrice: Double, strikeLimit: Double?) async -> OptionContract? {
        // Try real option chain first
        if let real = await findEligibleContract(symbol: symbol, optionType: optionType,
                                                 stockPrice: stockPrice, strikeLimit: strikeLimit) {
            log("\(symbol) using real chain contract")
            return real
        }

        // Fallback: synthetic contract using Black-Scholes
        log("\(symbol) option chain failed — using synthetic contract")
        return synthesizeContract(symbol: symbol, optionType: optionType, stockPrice: stockPrice)
    }

    /// Generate a synthetic option contract using Black-Scholes pricing
    private func synthesizeContract(symbol: String, optionType: OptionType, stockPrice: Double) -> OptionContract? {
        guard stockPrice > 0 else { return nil }

        let dte = config.targetDTE
        let t = Double(dte) / 365.0

        // Fetch historical vol if possible, otherwise use 30% annual default
        // (we can't await here easily, so use a reasonable default)
        let annualVol = 0.30  // conservative default

        // Calculate strike from target delta using inverse normal
        let zScore = invNormalCDF(1.0 - config.targetDelta)
        let stdMove = stockPrice * annualVol * sqrt(t)

        let strike: Double
        switch optionType {
        case .put:
            strike = ((stockPrice - zScore * stdMove) * 2).rounded() / 2  // round to $0.50
        case .call:
            strike = ((stockPrice + zScore * stdMove) * 2).rounded() / 2
        }

        guard strike > 0 else { return nil }

        // Black-Scholes pricing
        let d1 = (Foundation.log(stockPrice / strike) + (0.5 * annualVol * annualVol) * t) / (annualVol * sqrt(t))
        let d2 = d1 - annualVol * sqrt(t)

        let premium: Double
        switch optionType {
        case .call:
            premium = max(0.05, stockPrice * normalCDF(d1) - strike * normalCDF(d2))
        case .put:
            premium = max(0.05, strike * normalCDF(-d2) - stockPrice * normalCDF(-d1))
        }

        let expiration = Calendar.current.date(byAdding: .day, value: dte, to: Date())!

        log("\(symbol) synthetic: strike=\(fmtStrike(strike)) premium=\(fmtPrice(premium)) dte=\(dte)")

        return OptionContract(
            symbol: symbol,
            optionType: optionType,
            strike: strike,
            expiration: expiration,
            delta: config.targetDelta,
            premium: premium,
            openInterest: 0,
            impliedVol: annualVol
        )
    }

    // MARK: - Find Eligible Contract (Yahoo chain)

    func findEligibleContract(symbol: String, optionType: OptionType,
                              stockPrice: Double, strikeLimit: Double?) async -> OptionContract? {
        guard stockPrice > 0 else {
            log("\(symbol) findEligible: stockPrice is 0")
            return nil
        }

        let chain: OptionChainData
        do {
            chain = try await yahoo.fetchOptionChain(symbol: symbol)
        } catch {
            log("\(symbol) option chain fetch failed: \(error.localizedDescription)")
            return nil
        }

        guard !chain.expirations.isEmpty else {
            log("\(symbol) no expirations in chain")
            return nil
        }

        // Find expiration closest to target DTE
        let targetDTE = config.targetDTE
        let sortedExps = chain.expirations.sorted()
        guard let bestExp = sortedExps.min(by: {
            abs(Calendar.current.dateComponents([.day], from: Date(), to: $0).day! - targetDTE)
            < abs(Calendar.current.dateComponents([.day], from: Date(), to: $1).day! - targetDTE)
        }) else {
            log("\(symbol) no best expiration found")
            return nil
        }

        // Fetch chain for that specific expiration
        let expChain: OptionChainData
        do {
            expChain = try await yahoo.fetchOptionChain(symbol: symbol, expiration: bestExp)
        } catch {
            log("\(symbol) expiration chain fetch failed: \(error.localizedDescription)")
            return nil
        }

        let quotes = optionType == .put ? expChain.puts : expChain.calls
        log("\(symbol) got \(quotes.count) \(optionType.rawValue) quotes for exp \(bestExp)")

        guard !quotes.isEmpty else {
            log("\(symbol) no quotes for \(optionType.rawValue)")
            return nil
        }

        // Filter by open interest and strike limit
        let filtered = quotes.filter { q in
            q.openInterest >= config.minOpenInterest &&
            q.midpoint > 0 &&
            (strikeLimit == nil || strikeLimit! <= 0 ||
             (optionType == .put ? q.strike <= strikeLimit! : q.strike >= strikeLimit!))
        }

        log("\(symbol) \(filtered.count) quotes after filter (OI>=\(config.minOpenInterest), strikeLimit=\(strikeLimit.map { fmtPrice($0) } ?? "none"))")

        // Find contract closest to target delta
        let target = config.targetDelta
        if let best = filtered.min(by: { abs($0.delta - target) < abs($1.delta - target) }) {
            return OptionContract(
                symbol: symbol, optionType: optionType,
                strike: best.strike, expiration: best.expiration,
                delta: best.delta, premium: best.midpoint,
                openInterest: best.openInterest, impliedVol: best.impliedVol
            )
        }

        // Fallback: pick OTM strike by distance from price (ignoring OI filter)
        log("\(symbol) trying fallback by strike distance")
        return selectByStrikeDistance(quotes: quotes, stockPrice: stockPrice,
                                     optionType: optionType, expiration: bestExp, symbol: symbol)
    }

    /// Fallback: select strike by distance from stock price (approximating delta)
    private func selectByStrikeDistance(quotes: [OptionQuote], stockPrice: Double,
                                       optionType: OptionType, expiration: Date, symbol: String) -> OptionContract? {
        let otmFactor = optionType == .put ? (1.0 - config.targetDelta * 0.3) : (1.0 + config.targetDelta * 0.3)
        let targetStrike = stockPrice * otmFactor

        let otm = quotes.filter { q in
            q.midpoint > 0 &&
            (optionType == .put ? q.strike < stockPrice : q.strike > stockPrice)
        }

        guard let best = otm.min(by: {
            abs($0.strike - targetStrike) < abs($1.strike - targetStrike)
        }) else {
            log("\(symbol) no OTM quotes found at all")
            return nil
        }

        return OptionContract(
            symbol: symbol, optionType: optionType,
            strike: best.strike, expiration: expiration,
            delta: best.delta, premium: best.midpoint,
            openInterest: best.openInterest, impliedVol: best.impliedVol
        )
    }

    // MARK: - Calculate Quantity

    private func calculateQuantity(position: WheelPosition, optionType: OptionType,
                                   stockPrice: Double, nlv: Double, cash: Double) -> Int {
        guard stockPrice > 0 else { return 0 }

        switch optionType {
        case .put:
            let targetValue = position.weight * config.buyingPower(nlv: nlv)
            let targetShares = Int(targetValue / stockPrice)
            let targetContracts = max(1, targetShares / 100)

            let maxValue = config.maxNewContractValue(nlv: nlv)
            let maxContracts = max(1, Int(maxValue / (stockPrice * 100)))

            // Cash needed to cover assignment
            let cashContracts = Int(cash / (stockPrice * 100))

            let result = min(targetContracts, min(maxContracts, max(0, cashContracts)))
            log("\(position.symbol) qty calc: target=\(targetContracts), max=\(maxContracts), cash=\(cashContracts) → \(result)")
            return result

        case .call:
            let maxCalls = Int(Double(position.shares) / 100.0 * config.callCapFactor)
            return max(0, maxCalls)
        }
    }

    // MARK: - Strike Limit Calculation

    private func calculateStrikeLimit(position: WheelPosition, optionType: OptionType) -> Double? {
        switch optionType {
        case .put:
            return position.currentPrice  // stay OTM
        case .call:
            if config.maintainHighWaterMark && position.avgCost > 0 {
                return position.avgCost
            }
            return position.currentPrice
        }
    }

    // MARK: - Premium Estimation

    func estimateCurrentPremium(option: ActiveOption, stockPrice: Double) -> Double {
        let contract = option.contract
        let dte = max(1, contract.dte)
        let originalDTE = max(1, Calendar.current.dateComponents(
            [.day], from: option.openDate, to: contract.expiration
        ).day ?? 45)

        let timeRatio = Double(dte) / Double(originalDTE)
        let timeFactor = sqrt(timeRatio)

        let intrinsic: Double
        switch contract.optionType {
        case .put:  intrinsic = max(0, contract.strike - stockPrice)
        case .call: intrinsic = max(0, stockPrice - contract.strike)
        }

        let originalExtrinsic = max(0, option.openPremium - max(0, contract.optionType == .put
            ? contract.strike - stockPrice : stockPrice - contract.strike))
        let currentExtrinsic = originalExtrinsic * timeFactor

        return intrinsic + currentExtrinsic
    }

    // MARK: - Volatility Calculation

    func calculateDailyStdDev(symbol: String) async -> Double? {
        guard let prices = try? await yahoo.fetchHistory(symbol: symbol, days: config.dailyStddevWindow + 10) else {
            return nil
        }
        guard prices.count >= 2 else { return nil }

        var logReturns: [Double] = []
        for i in 1..<prices.count {
            if prices[i] > 0 && prices[i-1] > 0 {
                logReturns.append(Foundation.log(prices[i] / prices[i-1]))
            }
        }

        guard logReturns.count >= 2 else { return nil }
        let mean = logReturns.reduce(0, +) / Double(logReturns.count)
        let variance = logReturns.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(logReturns.count - 1)
        return sqrt(variance)
    }

    // MARK: - Normal Distribution Helpers

    private func normalCDF(_ x: Double) -> Double {
        return 0.5 * erfc(-x / sqrt(2.0))
    }

    private func invNormalCDF(_ p: Double) -> Double {
        guard p > 0 && p < 1 else { return 0 }
        let a: [Double] = [-3.969683028665376e+01, 2.209460984245205e+02,
                           -2.759285104469687e+02, 1.383577518672690e+02,
                           -3.066479806614716e+01, 2.506628277459239e+00]
        let b: [Double] = [-5.447609879822406e+01, 1.615858368580409e+02,
                           -1.556989798598866e+02, 6.680131188771972e+01,
                           -1.328068155288572e+01]
        let c: [Double] = [-7.784894002430293e-03, -3.223964580411365e-01,
                           -2.400758277161838e+00, -2.549732539343734e+00,
                           4.374664141464968e+00,  2.938163982698783e+00]
        let d: [Double] = [7.784695709041462e-03, 3.224671290700398e-01,
                           2.445134137142996e+00, 3.754408661907416e+00]
        let pLow = 0.02425
        let pHigh = 1 - pLow
        if p < pLow {
            let q = sqrt(-2 * Foundation.log(p))
            return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) /
                   ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
        } else if p <= pHigh {
            let q = p - 0.5
            let r = q * q
            return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q /
                   (((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1)
        } else {
            let q = sqrt(-2 * Foundation.log(1 - p))
            return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) /
                    ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
        }
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
