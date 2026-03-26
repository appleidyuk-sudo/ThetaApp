// IVScanner.swift — Scans popular wheel candidates for high IV
// Ranks by implied volatility to suggest best premium-selling opportunities

import Foundation

struct IVCandidate: Identifiable {
    let id = UUID()
    let symbol: String
    let sector: Sector
    let price: Double
    let iv: Double              // annualized implied vol from ATM options
    let ivRank: Double          // 0–1 rank within scanned universe
    let premium30d: Double      // estimated 30-day ATM put premium
    let premiumYield: Double    // annualized premium yield %

    var ivLabel: String { String(format: "%.0f%%", iv * 100) }
    var yieldLabel: String { String(format: "%.1f%%", premiumYield * 100) }
}

actor IVScanner {
    static let shared = IVScanner()

    // Popular wheel-friendly tickers: liquid, optionable, well-known
    // Covers mega-cap tech, semis, financials, energy, consumer, ETFs
    static let wheelUniverse: [String] = [
        // Tech / Software
        "AAPL", "MSFT", "AMZN", "GOOGL", "META", "TSLA",
        "PLTR", "SOFI", "SNAP", "UBER", "COIN", "HOOD", "MARA",
        "APP", "SHOP", "CRWD", "NET", "DDOG", "SNOW",
        // Semiconductors
        "NVDA", "AMD", "INTC", "MU", "AVGO", "QCOM", "MRVL", "ARM", "SMCI",
        // Financials
        "JPM", "BAC", "GS", "C", "WFC", "SCHW",
        // Energy
        "XOM", "CVX", "OXY", "SLB", "DVN",
        // Consumer / Retail
        "NKE", "DIS", "SBUX", "TGT", "WMT", "COST",
        // Healthcare
        "PFE", "JNJ", "ABBV", "MRK",
        // ETFs (great for wheel)
        "SPY", "QQQ", "IWM", "EEM", "XLF", "XLE", "GDX", "SLV", "TQQQ",
        // High IV favorites
        "MSTR", "RIVN", "LCID", "NIO", "BABA", "GME", "AMC",
    ]

    private let yahoo = YahooFinanceService.shared

    /// Scan full universe and return ALL candidates sorted by IV (highest first)
    func scanHighIV() async -> [IVCandidate] {
        var candidates: [IVCandidate] = []

        // Fetch in parallel batches of 8 to avoid throttling
        let batchSize = 8
        let batches = stride(from: 0, to: Self.wheelUniverse.count, by: batchSize).map {
            Array(Self.wheelUniverse[$0..<min($0 + batchSize, Self.wheelUniverse.count)])
        }

        for batch in batches {
            let results = await withTaskGroup(of: IVCandidate?.self) { group in
                for symbol in batch {
                    group.addTask { [self] in
                        await self.fetchCandidate(symbol: symbol)
                    }
                }
                var batchResults: [IVCandidate] = []
                for await result in group {
                    if let r = result { batchResults.append(r) }
                }
                return batchResults
            }
            candidates.append(contentsOf: results)

            // Small delay between batches to be nice to Yahoo
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        }

        // Sort by IV descending
        candidates.sort { $0.iv > $1.iv }

        // Calculate IV rank (percentile within scanned universe)
        let count = candidates.count
        for i in candidates.indices {
            let rank = 1.0 - (Double(i) / Double(max(1, count - 1)))
            candidates[i] = IVCandidate(
                symbol: candidates[i].symbol,
                sector: candidates[i].sector,
                price: candidates[i].price,
                iv: candidates[i].iv,
                ivRank: rank,
                premium30d: candidates[i].premium30d,
                premiumYield: candidates[i].premiumYield
            )
        }

        return candidates  // no cap — return all
    }

    /// Fetch IV data for a single symbol
    private func fetchCandidate(symbol: String) async -> IVCandidate? {
        do {
            // Get stock price
            let quote = try await yahoo.fetchQuote(symbol: symbol)
            let price = quote.price
            guard price > 0 else { return nil }

            // Get option chain for nearest monthly expiration
            let chain = try await yahoo.fetchOptionChain(symbol: symbol)
            guard !chain.puts.isEmpty else { return nil }

            // Find ATM put (closest strike to current price)
            let atmPut = chain.puts.min(by: {
                abs($0.strike - price) < abs($1.strike - price)
            })

            guard let atm = atmPut, atm.impliedVol > 0 else { return nil }

            // Calculate annualized premium yield
            // premium yield = (premium / strike) * (365 / DTE) for annualization
            let dte = max(1, Calendar.current.dateComponents([.day], from: Date(), to: atm.expiration).day ?? 30)
            let premiumYield = (atm.midpoint / price) * (365.0 / Double(dte))

            // Estimate 30-day ATM premium using IV
            // P ≈ S * IV * sqrt(T/365) * 0.4 (rough ATM put approximation)
            let t30 = 30.0 / 365.0
            let premium30d = price * atm.impliedVol * sqrt(t30) * 0.4

            return IVCandidate(
                symbol: symbol,
                sector: sectorFor(symbol),
                price: price,
                iv: atm.impliedVol,
                ivRank: 0, // will be set after sorting
                premium30d: premium30d,
                premiumYield: premiumYield
            )
        } catch {
            return nil
        }
    }

    /// Quick scan of a curated subset for faster initial loading — returns ALL results
    func quickScan() async -> [IVCandidate] {
        let quickList = ["TSLA", "NVDA", "AMD", "MU", "APP", "COIN", "PLTR",
                         "MSTR", "SOFI", "SMCI", "RIVN", "MARA", "ARM",
                         "SPY", "QQQ", "IWM", "GME", "AVGO", "CRWD", "SNAP"]

        let results = await withTaskGroup(of: IVCandidate?.self) { group in
            for symbol in quickList {
                group.addTask { [self] in
                    await self.fetchCandidate(symbol: symbol)
                }
            }
            var all: [IVCandidate] = []
            for await result in group {
                if let r = result { all.append(r) }
            }
            return all
        }

        return results.sorted { $0.iv > $1.iv }  // no cap — return all
    }
}
