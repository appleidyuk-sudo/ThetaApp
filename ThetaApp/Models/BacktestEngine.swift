// BacktestEngine.swift — Historical backtest of The Wheel strategy
// Uses Yahoo Finance historical data to simulate wheel trades over time

import Foundation

// MARK: - Backtest Result

struct BacktestResult: Identifiable {
    let id = UUID()
    let symbol: String
    let startDate: Date
    let endDate: Date
    let startingCash: Double
    let finalNLV: Double
    let totalReturn: Double       // fraction
    let annualizedReturn: Double  // fraction
    let totalPremium: Double
    let totalTrades: Int
    let wheelCycles: Int
    let maxDrawdown: Double       // fraction (negative)
    let winRate: Double           // fraction of profitable trades
    let avgDaysInTrade: Double
    let sharpeRatio: Double
    let dailySnapshots: [BacktestSnapshot]
    let trades: [BacktestTrade]

    var totalReturnPct: String { fmtSignedPct(totalReturn) }
    var annualizedPct: String { fmtSignedPct(annualizedReturn) }
    var maxDrawdownPct: String { fmtSignedPct(maxDrawdown) }
    var winRatePct: String { fmtPct(winRate) }
}

struct BacktestSnapshot: Identifiable {
    let id = UUID()
    let date: Date
    let nlv: Double
    let cash: Double
    let stockValue: Double
    let cumulativePremium: Double
}

struct BacktestTrade: Identifiable {
    let id = UUID()
    let date: Date
    let action: String          // "STO PUT", "STO CALL", "ROLL", "ASSIGNED", "CALLED", "EXPIRED"
    let strike: Double
    let premium: Double
    let pnl: Double
    let note: String
}

// MARK: - Backtest Configuration

struct BacktestConfig {
    let symbol: String
    let startDate: Date
    let endDate: Date
    let startingCash: Double
    let targetDelta: Double
    let targetDTE: Int
    let rollPnlTarget: Double
    let rollDTE: Int
    let callCapFactor: Double

    static func from(config: ThetaConfig, symbol: String, months: Int) -> BacktestConfig {
        let end = Date()
        let start = Calendar.current.date(byAdding: .month, value: -months, to: end)!
        return BacktestConfig(
            symbol: symbol,
            startDate: start,
            endDate: end,
            startingCash: config.startingCash,
            targetDelta: config.targetDelta,
            targetDTE: config.targetDTE,
            rollPnlTarget: config.rollPnlTarget,
            rollDTE: config.rollDTE,
            callCapFactor: config.callCapFactor
        )
    }
}

// MARK: - Backtest Engine

actor BacktestEngine {
    private let yahoo = YahooFinanceService.shared

    // MARK: - Run Backtest

    func run(config: BacktestConfig) async throws -> BacktestResult {
        // Fetch historical prices
        let prices = try await fetchHistoricalPrices(symbol: config.symbol, start: config.startDate, end: config.endDate)
        guard prices.count >= 20 else {
            throw BacktestError.insufficientData
        }

        // Calculate historical volatility for option pricing
        let hvDaily = calculateHistoricalVol(prices: prices.map { $0.close })

        // Simulation state
        var cash = config.startingCash
        var shares = 0
        var avgCost: Double = 0
        var phase: WheelPhase = .sellingPuts
        var activeStrike: Double = 0
        var activeExpDate: Date = config.startDate
        var activePremium: Double = 0
        var activeType: OptionType = .put
        var cumulativePremium: Double = 0
        var wheelCycles = 0

        var snapshots: [BacktestSnapshot] = []
        var trades: [BacktestTrade] = []
        var peakNLV = config.startingCash
        var maxDrawdown: Double = 0
        var dailyReturns: [Double] = []
        var prevNLV = config.startingCash
        var totalDaysInTrades = 0
        var tradeCount = 0
        var winCount = 0

        // Walk through each day
        for (i, day) in prices.enumerated() {
            let price = day.close
            let stockValue = Double(shares) * price
            let nlv = cash + stockValue

            // Track daily returns for Sharpe
            if i > 0 {
                let dailyRet = (nlv - prevNLV) / prevNLV
                dailyReturns.append(dailyRet)
            }
            prevNLV = nlv

            // Track drawdown
            peakNLV = max(peakNLV, nlv)
            let dd = (nlv - peakNLV) / peakNLV
            maxDrawdown = min(maxDrawdown, dd)

            // Snapshot
            snapshots.append(BacktestSnapshot(
                date: day.date, nlv: nlv, cash: cash,
                stockValue: stockValue, cumulativePremium: cumulativePremium
            ))

            // Check if active option expires today
            if activeStrike > 0 && day.date >= activeExpDate {
                let result = handleExpiration(
                    price: price, strike: activeStrike, optionType: activeType,
                    premium: activePremium, shares: &shares, cash: &cash,
                    avgCost: &avgCost, phase: &phase, cycles: &wheelCycles
                )
                trades.append(BacktestTrade(
                    date: day.date, action: result.action, strike: activeStrike,
                    premium: result.premium, pnl: result.pnl, note: result.note
                ))
                tradeCount += 1
                if result.pnl > 0 { winCount += 1 }
                activeStrike = 0
                activePremium = 0
            }

            // Check roll eligibility on active option
            if activeStrike > 0 {
                let daysToExp = Calendar.current.dateComponents([.day], from: day.date, to: activeExpDate).day ?? 0
                let estimatedCurrent = estimateOptionValue(
                    type: activeType, strike: activeStrike,
                    price: price, daysToExp: daysToExp, vol: hvDaily
                )
                let pnlPct = activePremium > 0 ? (activePremium - estimatedCurrent) / activePremium : 0

                // Roll if P&L target hit or DTE trigger
                if pnlPct >= config.rollPnlTarget || daysToExp <= config.rollDTE {
                    // Close current
                    let closeCost = estimatedCurrent * 100.0
                    cash -= closeCost
                    totalDaysInTrades += Calendar.current.dateComponents(
                        [.day], from: activeExpDate.addingTimeInterval(-Double(config.targetDTE) * 86400),
                        to: day.date
                    ).day ?? 0

                    // Open new
                    let newExp = Calendar.current.date(byAdding: .day, value: config.targetDTE, to: day.date)!
                    let newStrike = calculateStrike(
                        price: price, type: activeType, delta: config.targetDelta,
                        daysToExp: config.targetDTE, vol: hvDaily,
                        avgCost: avgCost, phase: phase
                    )
                    let newPremium = estimateOptionValue(
                        type: activeType, strike: newStrike,
                        price: price, daysToExp: config.targetDTE, vol: hvDaily
                    )

                    let netCredit = newPremium * 100.0 - closeCost
                    cash += newPremium * 100.0
                    cumulativePremium += newPremium * 100.0

                    trades.append(BacktestTrade(
                        date: day.date, action: "ROLL",
                        strike: newStrike, premium: newPremium,
                        pnl: netCredit,
                        note: "Rolled \(fmtStrike(activeStrike))→\(fmtStrike(newStrike)) pnl=\(fmtPct(pnlPct))"
                    ))
                    tradeCount += 1
                    if netCredit > 0 { winCount += 1 }

                    activeStrike = newStrike
                    activeExpDate = newExp
                    activePremium = newPremium
                }
            }

            // Write new option if none active
            if activeStrike == 0 {
                let optType: OptionType
                switch phase {
                case .sellingPuts, .idle, .calledAway:
                    optType = .put
                    phase = .sellingPuts
                case .assigned, .sellingCalls:
                    optType = .call
                    phase = .sellingCalls
                }

                let expDate = Calendar.current.date(byAdding: .day, value: config.targetDTE, to: day.date)!
                let strike = calculateStrike(
                    price: price, type: optType, delta: config.targetDelta,
                    daysToExp: config.targetDTE, vol: hvDaily,
                    avgCost: avgCost, phase: phase
                )
                let premium = estimateOptionValue(
                    type: optType, strike: strike,
                    price: price, daysToExp: config.targetDTE, vol: hvDaily
                )

                guard premium > 0.05 else { continue }  // minimum credit

                activeStrike = strike
                activeExpDate = expDate
                activePremium = premium
                activeType = optType

                cash += premium * 100.0
                cumulativePremium += premium * 100.0

                let typeLabel = optType == .put ? "STO PUT" : "STO CALL"
                trades.append(BacktestTrade(
                    date: day.date, action: typeLabel,
                    strike: strike, premium: premium, pnl: 0,
                    note: "\(typeLabel) \(fmtStrike(strike)) for \(fmtPrice(premium)) \(config.targetDTE)DTE"
                ))
            }
        }

        // Final calculations
        let finalPrice = prices.last?.close ?? 0
        let finalStockValue = Double(shares) * finalPrice
        let finalNLV = cash + finalStockValue

        let totalReturn = (finalNLV - config.startingCash) / config.startingCash
        let dayCount = Calendar.current.dateComponents([.day], from: config.startDate, to: config.endDate).day ?? 365
        let years = Double(dayCount) / 365.25
        let annualizedReturn = years > 0 ? pow(1.0 + totalReturn, 1.0 / years) - 1.0 : totalReturn

        // Sharpe ratio (annualized, assuming 0% risk-free)
        let avgReturn = dailyReturns.isEmpty ? 0 : dailyReturns.reduce(0, +) / Double(dailyReturns.count)
        let variance = dailyReturns.isEmpty ? 1 : dailyReturns.map { ($0 - avgReturn) * ($0 - avgReturn) }.reduce(0, +) / Double(dailyReturns.count)
        let dailyStdDev = sqrt(variance)
        let sharpe = dailyStdDev > 0 ? (avgReturn / dailyStdDev) * sqrt(252) : 0

        let avgDays = tradeCount > 0 ? Double(totalDaysInTrades) / Double(tradeCount) : 0
        let winRate = tradeCount > 0 ? Double(winCount) / Double(tradeCount) : 0

        return BacktestResult(
            symbol: config.symbol,
            startDate: config.startDate,
            endDate: config.endDate,
            startingCash: config.startingCash,
            finalNLV: finalNLV,
            totalReturn: totalReturn,
            annualizedReturn: annualizedReturn,
            totalPremium: cumulativePremium,
            totalTrades: tradeCount,
            wheelCycles: wheelCycles,
            maxDrawdown: maxDrawdown,
            winRate: winRate,
            avgDaysInTrade: avgDays,
            sharpeRatio: sharpe,
            dailySnapshots: snapshots,
            trades: trades
        )
    }

    // MARK: - Expiration Handler

    private struct ExpirationResult {
        let action: String
        let premium: Double
        let pnl: Double
        let note: String
    }

    private func handleExpiration(
        price: Double, strike: Double, optionType: OptionType,
        premium: Double, shares: inout Int, cash: inout Double,
        avgCost: inout Double, phase: inout WheelPhase, cycles: inout Int
    ) -> ExpirationResult {
        let isITM = optionType == .put ? price < strike : price > strike

        if isITM {
            switch optionType {
            case .put:
                // Assigned — buy 100 shares
                shares += 100
                avgCost = strike
                cash -= strike * 100
                phase = .assigned
                return ExpirationResult(
                    action: "ASSIGNED", premium: 0, pnl: 0,
                    note: "Put assigned: bought 100 @ \(fmtPrice(strike))"
                )
            case .call:
                // Called away — sell shares
                let saleProceeds = strike * Double(min(shares, 100))
                let costBasis = avgCost * Double(min(shares, 100))
                let stockPnl = saleProceeds - costBasis
                cash += saleProceeds
                shares = max(0, shares - 100)
                if shares <= 0 {
                    phase = .calledAway
                    avgCost = 0
                    cycles += 1
                }
                return ExpirationResult(
                    action: "CALLED", premium: 0, pnl: stockPnl + premium * 100,
                    note: "Called away @ \(fmtPrice(strike)) stock P&L: \(fmtPrice(stockPnl))"
                )
            }
        } else {
            // Expired worthless — keep premium
            return ExpirationResult(
                action: "EXPIRED", premium: premium, pnl: premium * 100,
                note: "Expired OTM — kept \(fmtPrice(premium * 100))"
            )
        }
    }

    // MARK: - Option Pricing (Black-Scholes approximation)

    private func estimateOptionValue(type: OptionType, strike: Double,
                                     price: Double, daysToExp: Int, vol: Double) -> Double {
        let t = Double(max(1, daysToExp)) / 365.0
        let annualVol = vol * sqrt(252.0)
        guard annualVol > 0, price > 0, strike > 0 else { return 0 }

        // Simplified Black-Scholes
        let d1 = (log(price / strike) + (0.5 * annualVol * annualVol) * t) / (annualVol * sqrt(t))
        let d2 = d1 - annualVol * sqrt(t)

        let nd1 = normalCDF(d1)
        let nd2 = normalCDF(d2)

        switch type {
        case .call:
            return max(0, price * nd1 - strike * nd2)
        case .put:
            return max(0, strike * normalCDF(-d2) - price * normalCDF(-d1))
        }
    }

    private func calculateStrike(price: Double, type: OptionType, delta: Double,
                                 daysToExp: Int, vol: Double,
                                 avgCost: Double, phase: WheelPhase) -> Double {
        let annualVol = vol * sqrt(252.0)
        let t = Double(max(1, daysToExp)) / 365.0
        let stdMove = price * annualVol * sqrt(t)

        // Approximate strike from target delta
        // For puts: strike ≈ price - (invNormalCDF(1-delta) * stdMove)
        // For calls: strike ≈ price + (invNormalCDF(1-delta) * stdMove)
        let zScore = invNormalCDF(1.0 - delta)

        switch type {
        case .put:
            let strike = price - zScore * stdMove
            // Round to nearest $0.50
            return (strike * 2).rounded() / 2
        case .call:
            var strike = price + zScore * stdMove
            // Maintain high water mark: don't sell below cost basis
            if avgCost > 0 && phase == .sellingCalls {
                strike = max(strike, avgCost)
            }
            return (strike * 2).rounded() / 2
        }
    }

    // MARK: - Historical Vol

    private func calculateHistoricalVol(prices: [Double]) -> Double {
        guard prices.count >= 2 else { return 0.25 / sqrt(252) }  // default ~25% annual
        var logReturns: [Double] = []
        for i in 1..<prices.count {
            if prices[i] > 0 && prices[i-1] > 0 {
                logReturns.append(log(prices[i] / prices[i-1]))
            }
        }
        guard logReturns.count >= 2 else { return 0.25 / sqrt(252) }
        let mean = logReturns.reduce(0, +) / Double(logReturns.count)
        let variance = logReturns.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(logReturns.count - 1)
        return sqrt(variance)
    }

    // MARK: - Fetch Historical Prices

    struct HistoricalPrice {
        let date: Date
        let close: Double
    }

    private func fetchHistoricalPrices(symbol: String, start: Date, end: Date) async throws -> [HistoricalPrice] {
        let p1 = Int(start.timeIntervalSince1970)
        let p2 = Int(end.timeIntervalSince1970)
        let urlStr = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?period1=\(p1)&period2=\(p2)&interval=1d"

        guard let url = URL(string: urlStr) else { throw BacktestError.invalidSymbol }

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        ]
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(from: url)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw BacktestError.fetchFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let chart = json?["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first,
              let timestamps = result["timestamp"] as? [Int],
              let indicators = result["indicators"] as? [String: Any],
              let adjclose = indicators["adjclose"] as? [[String: Any]],
              let closes = adjclose.first?["adjclose"] as? [Double?]
        else {
            throw BacktestError.parseError
        }

        var prices: [HistoricalPrice] = []
        for (i, ts) in timestamps.enumerated() {
            if let close = closes[safe: i] ?? nil, close > 0 {
                prices.append(HistoricalPrice(
                    date: Date(timeIntervalSince1970: TimeInterval(ts)),
                    close: close
                ))
            }
        }

        return prices
    }

    // MARK: - Normal Distribution Helpers

    private func normalCDF(_ x: Double) -> Double {
        return 0.5 * erfc(-x / sqrt(2.0))
    }

    private func invNormalCDF(_ p: Double) -> Double {
        // Rational approximation (Abramowitz & Stegun 26.2.23)
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
            let q = sqrt(-2 * log(p))
            return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) /
                   ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
        } else if p <= pHigh {
            let q = p - 0.5
            let r = q * q
            return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q /
                   (((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1)
        } else {
            let q = sqrt(-2 * log(1 - p))
            return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) /
                    ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1)
        }
    }
}

// MARK: - Errors

enum BacktestError: LocalizedError {
    case insufficientData
    case invalidSymbol
    case fetchFailed
    case parseError

    var errorDescription: String? {
        switch self {
        case .insufficientData: return "Not enough historical data (need 20+ days)"
        case .invalidSymbol:    return "Invalid symbol"
        case .fetchFailed:      return "Failed to fetch historical data"
        case .parseError:       return "Failed to parse historical data"
        }
    }
}

// MARK: - Safe Array Access

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
