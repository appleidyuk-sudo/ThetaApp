// Config.swift — ThetaGang configuration ported to Swift
// Maps to thetagang.toml sections

import SwiftUI

class ThetaConfig: ObservableObject {

    // MARK: - Account
    @AppStorage("startingCash")     var startingCash: Double = 100_000
    @AppStorage("marginUsage")      var marginUsage: Double = 0.5  // 0.0–1.0

    // MARK: - Target
    @AppStorage("targetDelta")      var targetDelta: Double = 0.30
    @AppStorage("targetDTE")        var targetDTE: Int = 45
    @AppStorage("maxDTE")           var maxDTE: Int = 180
    @AppStorage("minOpenInterest")  var minOpenInterest: Int = 10

    // MARK: - Roll When
    @AppStorage("rollPnlTarget")    var rollPnlTarget: Double = 0.90  // 90%
    @AppStorage("rollDTE")          var rollDTE: Int = 15
    @AppStorage("rollMinPnl")       var rollMinPnl: Double = 0.0
    @AppStorage("rollPutsITM")      var rollPutsITM: Bool = true
    @AppStorage("rollCallsITM")     var rollCallsITM: Bool = true
    @AppStorage("rollCreditOnly")   var rollCreditOnly: Bool = false
    @AppStorage("maintainHWM")      var maintainHighWaterMark: Bool = true

    // MARK: - Write When
    @AppStorage("writePutsOnRed")   var writePutsOnRed: Bool = false
    @AppStorage("writeCallsOnGreen") var writeCallsOnGreen: Bool = false
    @AppStorage("callCapFactor")    var callCapFactor: Double = 1.0
    @AppStorage("maxNewContractsPct") var maxNewContractsPct: Double = 0.05

    // MARK: - Write Threshold
    @AppStorage("writeThreshold")       var writeThreshold: Double = 0.0  // 0 = disabled
    @AppStorage("writeThresholdSigma")  var writeThresholdSigma: Double = 0.0
    @AppStorage("dailyStddevWindow")    var dailyStddevWindow: Int = 30

    // MARK: - VIX Hedging
    @AppStorage("vixHedgeEnabled")      var vixHedgeEnabled: Bool = false
    @AppStorage("vixHedgeDelta")        var vixHedgeDelta: Double = 0.30
    @AppStorage("vixHedgeDTE")          var vixHedgeDTE: Int = 30
    @AppStorage("vixHedgeAllocation")   var vixHedgeAllocation: Double = 0.01
    @AppStorage("vixCloseAbove")        var vixCloseAbove: Double = 50.0

    // MARK: - Cash Management
    @AppStorage("cashMgmtEnabled")      var cashMgmtEnabled: Bool = false
    @AppStorage("cashMgmtFund")         var cashMgmtFund: String = "SGOV"
    @AppStorage("cashBuyThreshold")     var cashBuyThreshold: Double = 0.01
    @AppStorage("cashSellThreshold")    var cashSellThreshold: Double = 0.005

    // MARK: - Regime Rebalance
    @AppStorage("regimeEnabled")        var regimeEnabled: Bool = false
    @AppStorage("regimeLookbackDays")   var regimeLookbackDays: Int = 40
    @AppStorage("regimeSoftBand")       var regimeSoftBand: Double = 0.25
    @AppStorage("regimeHardBand")       var regimeHardBand: Double = 0.50

    // MARK: - Execution
    @AppStorage("refreshInterval")  var refreshInterval: Int = 15  // minutes
    @AppStorage("autoExecute")      var autoExecute: Bool = true
    @AppStorage("minimumCredit")    var minimumCredit: Double = 0.05

    // MARK: - Display
    @AppStorage("bgDarkness")       var bgDarkness: Double = 0.85

    // MARK: - Minimum credit filter
    func meetsMinimumCredit(_ premium: Double) -> Bool {
        premium >= minimumCredit
    }

    // MARK: - Buying power
    func buyingPower(nlv: Double) -> Double {
        nlv * marginUsage
    }

    // MARK: - Max new contract value
    func maxNewContractValue(nlv: Double) -> Double {
        nlv * maxNewContractsPct
    }
}
