// NotificationManager.swift — Push notifications for wheel trade events
// Adapted from DHCbot's NotificationManager pattern

import UserNotifications
import Foundation

final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let throttleKey = "theta_alert_timestamps"
    private let throttleInterval: TimeInterval = 6 * 3600  // 6-hour cooldown per alert type

    private init() {}

    // MARK: - Permission

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("Notification permission error: \(error)")
            }
        }
    }

    // MARK: - Trade Event Notifications

    /// New option written (STO)
    func notifyOptionWritten(symbol: String, contract: String, premium: Double) {
        let key = "sto_\(symbol)"
        guard !isThrottled(key) else { return }
        post(
            title: "📝 New Option Written",
            body: "\(symbol): STO \(contract) for \(fmtPrice(premium))/sh",
            id: "sto-\(symbol)-\(UUID().uuidString.prefix(8))"
        )
        markThrottled(key)
    }

    /// Option rolled
    func notifyRoll(symbol: String, from: String, to: String, netCredit: Double, reason: String) {
        let key = "roll_\(symbol)"
        guard !isThrottled(key) else { return }
        let creditLabel = netCredit >= 0 ? "credit \(fmtPrice(netCredit))" : "debit \(fmtPrice(abs(netCredit)))"
        post(
            title: "🔄 Option Rolled — \(reason)",
            body: "\(symbol): \(from) → \(to) net \(creditLabel)",
            id: "roll-\(symbol)-\(UUID().uuidString.prefix(8))"
        )
        markThrottled(key)
    }

    /// Put assigned — shares bought
    func notifyAssignment(symbol: String, shares: Int, strike: Double) {
        // No throttle on assignments — always important
        post(
            title: "⚡ Put Assigned!",
            body: "\(symbol): Bought \(shares) shares @ \(fmtPrice(strike)). Now selling covered calls.",
            id: "assign-\(symbol)-\(UUID().uuidString.prefix(8))"
        )
    }

    /// Called away — shares sold
    func notifyCalledAway(symbol: String, shares: Int, strike: Double, cyclePnl: Double) {
        // No throttle — always important
        let pnlLabel = cyclePnl >= 0 ? "+\(fmtPrice(cyclePnl))" : fmtPrice(cyclePnl)
        post(
            title: "🏁 Called Away — Cycle Complete",
            body: "\(symbol): Sold \(shares) shares @ \(fmtPrice(strike)). Cycle P&L: \(pnlLabel)",
            id: "called-\(symbol)-\(UUID().uuidString.prefix(8))"
        )
    }

    /// Option expired worthless
    func notifyExpired(symbol: String, contract: String, premiumKept: Double) {
        let key = "expired_\(symbol)"
        guard !isThrottled(key) else { return }
        post(
            title: "✅ Expired Worthless",
            body: "\(symbol): \(contract) expired OTM. Premium kept: \(fmtPrice(premiumKept))",
            id: "expired-\(symbol)-\(UUID().uuidString.prefix(8))"
        )
        markThrottled(key)
    }

    /// Roll eligibility alert — approaching trigger
    func notifyRollApproaching(symbol: String, contract: String, reason: String, dte: Int, pnlPct: Double) {
        let key = "rollwarn_\(symbol)"
        guard !isThrottled(key) else { return }
        post(
            title: "⏰ Roll Trigger Approaching",
            body: "\(symbol): \(contract) — \(reason) (DTE: \(dte), P&L: \(fmtSignedPct(pnlPct)))",
            id: "rollwarn-\(symbol)-\(UUID().uuidString.prefix(8))"
        )
        markThrottled(key)
    }

    /// Daily summary
    func notifyDailySummary(nlv: Double, dailyPnl: Double, tradesCount: Int, premiumToday: Double) {
        let key = "daily_summary"
        guard !isThrottled(key) else { return }
        let pnlLabel = dailyPnl >= 0 ? "+\(fmtDollar(dailyPnl))" : fmtDollar(dailyPnl)
        post(
            title: "📊 Daily Summary",
            body: "NLV: \(fmtDollar(nlv)) (\(pnlLabel)) · \(tradesCount) trades · Premium: \(fmtDollar(premiumToday))",
            id: "daily-\(UUID().uuidString.prefix(8))"
        )
        markThrottled(key)
    }

    /// No trades executed (informational, only if user has positions)
    func notifyNoTrades(positionCount: Int) {
        let key = "no_trades"
        guard !isThrottled(key) else { return }
        post(
            title: "🔍 Cycle Complete — No Trades",
            body: "\(positionCount) position(s) checked. No rolls, writes, or expirations triggered.",
            id: "notrades-\(UUID().uuidString.prefix(8))"
        )
        markThrottled(key)
    }

    // MARK: - Post Notification

    private func post(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil  // deliver immediately
        )

        center.add(request) { error in
            if let error {
                print("Notification error: \(error)")
            }
        }
    }

    // MARK: - Throttling

    private func isThrottled(_ key: String) -> Bool {
        let timestamps = getTimestamps()
        guard let lastFired = timestamps[key] else { return false }
        return Date().timeIntervalSince(lastFired) < throttleInterval
    }

    private func markThrottled(_ key: String) {
        var timestamps = getTimestamps()
        timestamps[key] = Date()
        // Clean up old entries
        let cutoff = Date().addingTimeInterval(-throttleInterval * 2)
        timestamps = timestamps.filter { $0.value > cutoff }
        saveTimestamps(timestamps)
    }

    private func getTimestamps() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: throttleKey),
              let dict = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return dict
    }

    private func saveTimestamps(_ timestamps: [String: Date]) {
        if let data = try? JSONEncoder().encode(timestamps) {
            UserDefaults.standard.set(data, forKey: throttleKey)
        }
    }
}
