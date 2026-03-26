// Models.swift — Core data models for ThetaApp
// Ported from thetagang (Python) with DHCbot UI patterns

import SwiftUI

// MARK: - Wheel Phase

enum WheelPhase: String, Codable, CaseIterable {
    case sellingPuts    = "Selling Puts"
    case assigned       = "Assigned"
    case sellingCalls   = "Selling Calls"
    case calledAway     = "Called Away"
    case idle           = "Idle"

    var color: Color {
        switch self {
        case .sellingPuts:   return AppColors.orange
        case .assigned:      return AppColors.yellow
        case .sellingCalls:  return AppColors.green
        case .calledAway:    return AppColors.blue
        case .idle:          return AppColors.muted
        }
    }

    var icon: String {
        switch self {
        case .sellingPuts:   return "arrow.down.circle.fill"
        case .assigned:      return "checkmark.circle.fill"
        case .sellingCalls:  return "arrow.up.circle.fill"
        case .calledAway:    return "arrow.right.circle.fill"
        case .idle:          return "minus.circle.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .sellingPuts:   return "CSP"
        case .assigned:      return "OWN"
        case .sellingCalls:  return "CC"
        case .calledAway:    return "DONE"
        case .idle:          return "IDLE"
        }
    }
}

// MARK: - Option Type

enum OptionType: String, Codable {
    case put = "PUT"
    case call = "CALL"

    var label: String { rawValue }
    var color: Color {
        self == .put ? AppColors.red : AppColors.green
    }
}

// MARK: - Trade Action

enum TradeAction: String, Codable {
    case sellToOpen  = "STO"
    case buyToClose  = "BTC"
    case assignment  = "ASSIGN"
    case calledAway  = "CALLED"
    case roll        = "ROLL"
    case expired     = "EXPIRED"

    var color: Color {
        switch self {
        case .sellToOpen:  return AppColors.green
        case .buyToClose:  return AppColors.red
        case .assignment:  return AppColors.yellow
        case .calledAway:  return AppColors.blue
        case .roll:        return AppColors.orange
        case .expired:     return AppColors.green
        }
    }
}

// MARK: - Roll Reason

enum RollReason: String, Codable {
    case pnlTarget   = "P&L Target"
    case dteTarget   = "DTE Target"
    case itm         = "ITM"
    case manual      = "Manual"
}

// MARK: - Option Contract

struct OptionContract: Identifiable, Codable {
    let id: UUID
    let symbol: String           // underlying
    let optionType: OptionType
    let strike: Double
    let expiration: Date
    let delta: Double
    let premium: Double          // per share (multiply by 100 for contract)
    let openInterest: Int
    let impliedVol: Double

    var dte: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expiration).day ?? 0
    }

    var contractPremium: Double { premium * 100.0 }

    var displayLabel: String {
        let df = DateFormatter()
        df.dateFormat = "M/d"
        let typeChar = optionType == .put ? "P" : "C"
        return "\(df.string(from: expiration)) \(typeChar) $\(fmtStrike(strike))"
    }

    init(symbol: String, optionType: OptionType, strike: Double, expiration: Date,
         delta: Double, premium: Double, openInterest: Int = 0, impliedVol: Double = 0) {
        self.id = UUID()
        self.symbol = symbol
        self.optionType = optionType
        self.strike = strike
        self.expiration = expiration
        self.delta = delta
        self.premium = premium
        self.openInterest = openInterest
        self.impliedVol = impliedVol
    }
}

// MARK: - Active Option Position

struct ActiveOption: Identifiable, Codable {
    let id: UUID
    let contract: OptionContract
    let quantity: Int             // negative = short
    let openDate: Date
    let openPremium: Double      // premium received per share at open
    var currentPremium: Double    // current market premium per share
    var isClosed: Bool
    var closeDate: Date?
    var closePremium: Double?
    var closeAction: TradeAction?

    var pnlPerShare: Double {
        if let cp = closePremium {
            return openPremium - cp  // short: profit = open - close
        }
        return openPremium - currentPremium
    }

    var pnlTotal: Double { pnlPerShare * 100.0 * Double(abs(quantity)) }

    var pnlPercent: Double {
        guard openPremium > 0 else { return 0 }
        return pnlPerShare / openPremium
    }

    var dte: Int { contract.dte }

    init(contract: OptionContract, quantity: Int, openPremium: Double) {
        self.id = UUID()
        self.contract = contract
        self.quantity = quantity
        self.openDate = Date()
        self.openPremium = openPremium
        self.currentPremium = openPremium
        self.isClosed = false
    }
}

// MARK: - Wheel Position (per symbol)

struct WheelPosition: Identifiable, Codable {
    let id: UUID
    let symbol: String
    let sector: Sector
    var weight: Double            // target portfolio weight (0.0–1.0)
    var phase: WheelPhase
    var shares: Int               // shares owned (0 if selling puts)
    var avgCost: Double           // average cost basis per share
    var currentPrice: Double
    var activeOptions: [ActiveOption]
    var tradeHistory: [TradeRecord]
    var totalPremiumCollected: Double
    var wheelCycleCount: Int      // number of completed cycles

    var marketValue: Double { Double(shares) * currentPrice }

    var unrealizedPnl: Double {
        guard shares > 0, avgCost > 0 else { return 0 }
        return Double(shares) * (currentPrice - avgCost)
    }

    var openOptionPnl: Double {
        activeOptions.filter { !$0.isClosed }.reduce(0) { $0 + $1.pnlTotal }
    }

    var currentActiveOption: ActiveOption? {
        activeOptions.first { !$0.isClosed }
    }

    init(symbol: String, weight: Double, sector: Sector? = nil) {
        self.id = UUID()
        self.symbol = symbol
        self.sector = sector ?? sectorFor(symbol)
        self.weight = weight
        self.phase = .idle
        self.shares = 0
        self.avgCost = 0
        self.currentPrice = 0
        self.activeOptions = []
        self.tradeHistory = []
        self.totalPremiumCollected = 0
        self.wheelCycleCount = 0
    }
}

// MARK: - Trade Record

struct TradeRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let symbol: String
    let action: TradeAction
    let optionType: OptionType?
    let strike: Double?
    let expiration: Date?
    let quantity: Int
    let price: Double            // per share
    let totalAmount: Double      // total cash impact
    let note: String

    init(date: Date = Date(), symbol: String, action: TradeAction,
         optionType: OptionType? = nil, strike: Double? = nil,
         expiration: Date? = nil, quantity: Int, price: Double,
         totalAmount: Double, note: String = "") {
        self.id = UUID()
        self.date = date
        self.symbol = symbol
        self.action = action
        self.optionType = optionType
        self.strike = strike
        self.expiration = expiration
        self.quantity = quantity
        self.price = price
        self.totalAmount = totalAmount
        self.note = note
    }
}

// MARK: - Portfolio Snapshot

struct PortfolioSnapshot: Identifiable, Codable {
    let id: UUID
    let date: Date
    let netLiquidation: Double
    let cash: Double
    let stockValue: Double
    let optionValue: Double
    let totalPremium: Double

    init(date: Date = Date(), nlv: Double, cash: Double,
         stockValue: Double, optionValue: Double, totalPremium: Double) {
        self.id = UUID()
        self.date = date
        self.netLiquidation = nlv
        self.cash = cash
        self.stockValue = stockValue
        self.optionValue = optionValue
        self.totalPremium = totalPremium
    }
}

// MARK: - Sector

enum Sector: String, Codable, CaseIterable, Comparable {
    case tech         = "Tech"
    case semis        = "Semis"
    case fintech      = "FinTech"
    case financials   = "Financials"
    case energy       = "Energy"
    case consumer     = "Consumer"
    case healthcare   = "Healthcare"
    case etf          = "ETF"
    case crypto       = "Crypto"
    case ev           = "EV"
    case meme         = "Meme"
    case unknown      = "Other"

    var color: Color {
        switch self {
        case .tech:        return AppColors.blue
        case .semis:       return AppColors.purple
        case .fintech:     return AppColors.cyan
        case .financials:  return AppColors.gold
        case .energy:      return AppColors.orange
        case .consumer:    return AppColors.pink
        case .healthcare:  return AppColors.green
        case .etf:         return AppColors.yellow
        case .crypto:      return AppColors.orange
        case .ev:          return AppColors.cyan
        case .meme:        return AppColors.red
        case .unknown:     return AppColors.muted
        }
    }

    static func < (lhs: Sector, rhs: Sector) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Lookup table: symbol → sector
let sectorMap: [String: Sector] = [
    // Tech / Software
    "AAPL": .tech, "MSFT": .tech, "AMZN": .tech, "GOOGL": .tech, "META": .tech,
    "TSLA": .tech, "PLTR": .tech, "SNAP": .tech, "UBER": .tech,
    "APP": .tech, "SHOP": .tech, "CRWD": .tech, "NET": .tech, "DDOG": .tech, "SNOW": .tech,
    // Semiconductors
    "NVDA": .semis, "AMD": .semis, "INTC": .semis, "MU": .semis,
    "AVGO": .semis, "QCOM": .semis, "MRVL": .semis, "ARM": .semis, "SMCI": .semis,
    // FinTech / Crypto-adjacent
    "SOFI": .fintech, "HOOD": .fintech, "COIN": .crypto, "MARA": .crypto, "MSTR": .crypto,
    // Financials
    "JPM": .financials, "BAC": .financials, "GS": .financials,
    "C": .financials, "WFC": .financials, "SCHW": .financials,
    // Energy
    "XOM": .energy, "CVX": .energy, "OXY": .energy, "SLB": .energy, "DVN": .energy,
    // Consumer / Retail
    "NKE": .consumer, "DIS": .consumer, "SBUX": .consumer,
    "TGT": .consumer, "WMT": .consumer, "COST": .consumer,
    // Healthcare
    "PFE": .healthcare, "JNJ": .healthcare, "ABBV": .healthcare, "MRK": .healthcare,
    // ETFs
    "SPY": .etf, "QQQ": .etf, "IWM": .etf, "EEM": .etf,
    "XLF": .etf, "XLE": .etf, "GDX": .etf, "SLV": .etf, "TQQQ": .etf,
    // EV
    "RIVN": .ev, "LCID": .ev, "NIO": .ev,
    // Meme
    "GME": .meme, "AMC": .meme, "BABA": .tech,
]

func sectorFor(_ symbol: String) -> Sector {
    sectorMap[symbol.uppercased()] ?? .unknown
}

// MARK: - Sort Options (Positions)

enum PositionSort: String, CaseIterable {
    case symbol  = "Name"
    case sector  = "Sector"
    case dte     = "DTE"
    case pnl     = "P&L"
}

// MARK: - Sort Options (Recommendations)

enum RecommendationSort: String, CaseIterable {
    case symbol  = "Name"
    case sector  = "Sector"
    case iv      = "IV"
    case yield   = "Yield"
}

// MARK: - App Colors (DHCbot style)

enum AppColors {
    static let green    = Color(red: 0.176, green: 0.800, blue: 0.439)  // #2DCC70
    static let red      = Color(red: 0.949, green: 0.271, blue: 0.271)  // #F24545
    static let yellow   = Color(red: 0.949, green: 0.765, blue: 0.024)  // #F2C306
    static let gold     = Color(red: 0.702, green: 0.604, blue: 0.200)  // #B39A33
    static let blue     = Color(red: 0.349, green: 0.329, blue: 0.624)  // #59549F
    static let purple   = Color(red: 0.600, green: 0.400, blue: 0.902)  // #9966E6
    static let cyan     = Color(red: 0.400, green: 0.800, blue: 0.800)  // #66CCCC
    static let orange   = Color(red: 0.902, green: 0.541, blue: 0.098)  // #E68A19
    static let pink     = Color(red: 0.851, green: 0.353, blue: 0.835)  // #D95AD5
    static let muted    = Color.white.opacity(0.35)
}

// MARK: - Formatting Helpers

func fmtPrice(_ v: Double) -> String {
    String(format: "$%.2f", v)
}

func fmtDollar(_ v: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: v)) ?? "$0"
}

func fmtPct(_ v: Double) -> String {
    String(format: "%.1f%%", v * 100)
}

func fmtSignedPct(_ v: Double) -> String {
    String(format: "%+.1f%%", v * 100)
}

func fmtQty(_ v: Double) -> String {
    v.truncatingRemainder(dividingBy: 1) == 0
        ? String(format: "%.0f", v)
        : String(format: "%.2f", v)
}

func fmtStrike(_ v: Double) -> String {
    v.truncatingRemainder(dividingBy: 1) == 0
        ? String(format: "%.0f", v)
        : String(format: "%.2f", v)
}

func fmtDelta(_ v: Double) -> String {
    String(format: "%.2f", v)
}

func fmtDTE(_ days: Int) -> String {
    "\(days)d"
}
