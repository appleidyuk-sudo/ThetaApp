// YahooFinance.swift — Yahoo Finance v8 chart + v7 options API
// Adapted from DHCbot's BollingerEngine pattern

import Foundation

// MARK: - Market Data

struct MarketQuote {
    let symbol: String
    let price: Double
    let previousClose: Double
    let dailyChange: Double       // absolute
    let dailyChangePct: Double    // fraction (0.01 = 1%)
    let volume: Int
    let timestamp: Date
}

struct OptionChainData {
    let symbol: String
    let expirations: [Date]
    let calls: [OptionQuote]
    let puts: [OptionQuote]
}

struct OptionQuote {
    let strike: Double
    let expiration: Date
    let optionType: OptionType
    let bid: Double
    let ask: Double
    let last: Double
    let volume: Int
    let openInterest: Int
    let impliedVol: Double
    let delta: Double
    let gamma: Double
    let theta: Double
    let vega: Double

    var midpoint: Double { (bid + ask) / 2.0 }
}

// MARK: - Yahoo Finance Service

actor YahooFinanceService {
    static let shared = YahooFinanceService()

    private let session: URLSession
    private var crumb: String?
    private var cookies: [HTTPCookie] = []

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Stock Price (v8 chart)

    func fetchQuote(symbol: String) async throws -> MarketQuote {
        let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?range=5d&interval=1d&includePrePost=true")!
        let (data, response) = try await session.data(from: url)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw YahooError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let chart = json?["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first,
              let meta = result["meta"] as? [String: Any],
              let regularMarketPrice = meta["regularMarketPrice"] as? Double,
              let previousClose = meta["chartPreviousClose"] as? Double
        else {
            throw YahooError.parseError
        }

        let volume: Int
        if let indicators = result["indicators"] as? [String: Any],
           let quotes = indicators["quote"] as? [[String: Any]],
           let q = quotes.first,
           let vols = q["volume"] as? [Int?] {
            volume = vols.compactMap { $0 }.last ?? 0
        } else {
            volume = 0
        }

        let change = regularMarketPrice - previousClose
        let changePct = previousClose > 0 ? change / previousClose : 0

        return MarketQuote(
            symbol: symbol,
            price: regularMarketPrice,
            previousClose: previousClose,
            dailyChange: change,
            dailyChangePct: changePct,
            volume: volume,
            timestamp: Date()
        )
    }

    // MARK: - Historical Prices (for volatility calculation)

    func fetchHistory(symbol: String, days: Int = 60) async throws -> [Double] {
        let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)?range=\(days)d&interval=1d")!
        let (data, _) = try await session.data(from: url)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let chart = json?["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let result = results.first,
              let indicators = result["indicators"] as? [String: Any],
              let adjclose = indicators["adjclose"] as? [[String: Any]],
              let closes = adjclose.first?["adjclose"] as? [Double?]
        else {
            throw YahooError.parseError
        }

        return closes.compactMap { $0 }
    }

    // MARK: - Option Chain (v7 finance/options)

    func fetchOptionChain(symbol: String, expiration: Date? = nil) async throws -> OptionChainData {
        var urlString = "https://query1.finance.yahoo.com/v7/finance/options/\(symbol)"
        if let exp = expiration {
            let epoch = Int(exp.timeIntervalSince1970)
            urlString += "?date=\(epoch)"
        }

        // Fetch crumb if needed
        if crumb == nil {
            try await fetchCrumb()
        }

        if let c = crumb {
            urlString += urlString.contains("?") ? "&crumb=\(c)" : "?crumb=\(c)"
        }

        guard let url = URL(string: urlString) else { throw YahooError.invalidURL }

        var request = URLRequest(url: url)
        if !cookies.isEmpty {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw YahooError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return try parseOptionChain(data: data, symbol: symbol)
    }

    // MARK: - Crumb Auth

    private func fetchCrumb() async throws {
        // Step 1: Get consent cookies
        let consentURL = URL(string: "https://fc.yahoo.com/")!
        let (_, consentResp) = try await session.data(from: consentURL)

        if let httpResp = consentResp as? HTTPURLResponse,
           let headerFields = httpResp.allHeaderFields as? [String: String],
           let respURL = consentResp.url {
            let newCookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: respURL)
            cookies.append(contentsOf: newCookies)
        }

        // Step 2: Get crumb
        let crumbURL = URL(string: "https://query2.finance.yahoo.com/v1/test/getcrumb")!
        var request = URLRequest(url: crumbURL)
        if !cookies.isEmpty {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (crumbData, _) = try await session.data(for: request)
        crumb = String(data: crumbData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Parse Option Chain

    private func parseOptionChain(data: Data, symbol: String) throws -> OptionChainData {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let optionChain = json?["optionChain"] as? [String: Any],
              let results = optionChain["result"] as? [[String: Any]],
              let result = results.first
        else {
            throw YahooError.parseError
        }

        // Parse expirations
        let expirationEpochs = result["expirationDates"] as? [Int] ?? []
        let expirations = expirationEpochs.map { Date(timeIntervalSince1970: TimeInterval($0)) }

        // Parse options
        var calls: [OptionQuote] = []
        var puts: [OptionQuote] = []

        if let options = result["options"] as? [[String: Any]], let opt = options.first {
            if let callData = opt["calls"] as? [[String: Any]] {
                calls = callData.compactMap { parseOptionQuote($0, type: .call) }
            }
            if let putData = opt["puts"] as? [[String: Any]] {
                puts = putData.compactMap { parseOptionQuote($0, type: .put) }
            }
        }

        return OptionChainData(symbol: symbol, expirations: expirations, calls: calls, puts: puts)
    }

    private func parseOptionQuote(_ dict: [String: Any], type: OptionType) -> OptionQuote? {
        guard let strike = dict["strike"] as? Double,
              let expEpoch = dict["expiration"] as? Int
        else { return nil }

        return OptionQuote(
            strike: strike,
            expiration: Date(timeIntervalSince1970: TimeInterval(expEpoch)),
            optionType: type,
            bid: dict["bid"] as? Double ?? 0,
            ask: dict["ask"] as? Double ?? 0,
            last: dict["lastPrice"] as? Double ?? 0,
            volume: dict["volume"] as? Int ?? 0,
            openInterest: dict["openInterest"] as? Int ?? 0,
            impliedVol: dict["impliedVolatility"] as? Double ?? 0,
            delta: estimateDelta(dict, type: type),
            gamma: 0,
            theta: 0,
            vega: 0
        )
    }

    /// Estimate delta from option data when Greeks aren't available
    private func estimateDelta(_ dict: [String: Any], type: OptionType) -> Double {
        // Yahoo sometimes provides Greeks directly
        if let delta = dict["delta"] as? Double { return delta }

        // Rough estimate: use ITM probability from implied vol
        // For puts: delta ≈ -(1 - callDelta), typically negative
        // We store absolute delta for simplicity
        let itm = dict["inTheMoney"] as? Bool ?? false
        if itm {
            return type == .put ? 0.60 : 0.60
        } else {
            return type == .put ? 0.25 : 0.25
        }
    }
}

// MARK: - Errors

enum YahooError: LocalizedError {
    case httpError(Int)
    case parseError
    case invalidURL
    case noData

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP \(code)"
        case .parseError:          return "Failed to parse response"
        case .invalidURL:          return "Invalid URL"
        case .noData:              return "No data returned"
        }
    }
}
