// PositionDetailView.swift — Detail sheet for a wheel position

import SwiftUI

struct PositionDetailView: View {
    let position: WheelPosition
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.lg) {
                        headerCard
                        activeOptionCard
                        sharesCard
                        tradeHistorySection
                    }
                    .padding()
                }
            }
            .navigationTitle(position.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppColors.gold)
                }
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: position.phase.icon)
                            .foregroundColor(position.phase.color)
                            .font(.system(size: 24))
                        Text(position.phase.rawValue)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(position.phase.color)
                    }
                    Text("Cycle #\(position.wheelCycleCount + 1)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(fmtPrice(position.currentPrice))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Weight: \(Int(position.weight * 100))%")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.gold)
                }
            }

            Divider().overlay(Color.white.opacity(DesignTokens.Border.light))

            HStack {
                detailStat("Premium", fmtDollar(position.totalPremiumCollected), AppColors.green)
                Spacer()
                detailStat("Unrealized", fmtDollar(position.unrealizedPnl),
                           position.unrealizedPnl >= 0 ? AppColors.green : AppColors.red)
                Spacer()
                detailStat("Cycles", "\(position.wheelCycleCount)", AppColors.orange)
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Active Option Card

    private var activeOptionCard: some View {
        Group {
            if let opt = position.currentActiveOption {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("ACTIVE OPTION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))

                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(opt.contract.displayLabel)
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(opt.contract.optionType.color)

                            HStack(spacing: 16) {
                                labelValue("Delta", fmtDelta(opt.contract.delta))
                                labelValue("DTE", fmtDTE(opt.dte))
                                labelValue("IV", fmtPct(opt.contract.impliedVol))
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("P&L")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                            Text(fmtDollar(opt.pnlTotal))
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundColor(opt.pnlTotal >= 0 ? AppColors.green : AppColors.red)
                            Text(fmtSignedPct(opt.pnlPercent))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(opt.pnlPercent >= 0 ? AppColors.green : AppColors.red)
                        }
                    }

                    // Roll eligibility
                    rollEligibilityBar(opt)
                }
                .padding()
                .cardStyle()
            } else {
                VStack(spacing: 8) {
                    Text("NO ACTIVE OPTION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    Text("Next cycle will write a new option")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .cardStyle()
            }
        }
    }

    private func rollEligibilityBar(_ opt: ActiveOption) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Roll Triggers")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                Spacer()
            }

            HStack(spacing: 12) {
                // P&L bar
                VStack(alignment: .leading, spacing: 2) {
                    Text("P&L \(fmtPct(opt.pnlPercent)) / \(fmtPct(0.90))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.1))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(opt.pnlPercent >= 0.90 ? AppColors.green : AppColors.orange)
                                .frame(width: geo.size.width * min(1, max(0, opt.pnlPercent / 0.90)))
                        }
                    }
                    .frame(height: 4)
                }

                // DTE bar
                VStack(alignment: .leading, spacing: 2) {
                    Text("DTE \(opt.dte) / 15")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.1))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(opt.dte <= 15 ? AppColors.red : AppColors.yellow)
                                .frame(width: geo.size.width * min(1, max(0, 1.0 - Double(opt.dte) / 45.0)))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    // MARK: - Shares Card

    private var sharesCard: some View {
        Group {
            if position.shares > 0 {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("SHARES")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))

                    HStack {
                        labelValue("Quantity", "\(position.shares)")
                        Spacer()
                        labelValue("Avg Cost", fmtPrice(position.avgCost))
                        Spacer()
                        labelValue("Mkt Value", fmtDollar(position.marketValue))
                        Spacer()
                        let pnl = position.unrealizedPnl
                        labelValue("Unrealized", fmtDollar(pnl),
                                   color: pnl >= 0 ? AppColors.green : AppColors.red)
                    }
                }
                .padding()
                .cardStyle()
            }
        }
    }

    // MARK: - Trade History

    private var tradeHistorySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("TRADE HISTORY")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(DesignTokens.Text.muted))

            let positionTrades = position.tradeHistory
            if positionTrades.isEmpty {
                // Show from active options' context
                let closedOpts = position.activeOptions.filter { $0.isClosed }
                if closedOpts.isEmpty {
                    Text("No trades yet")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(closedOpts) { opt in
                        closedOptionRow(opt)
                    }
                }
            } else {
                ForEach(positionTrades) { trade in
                    tradeHistoryRow(trade)
                }
            }
        }
    }

    private func closedOptionRow(_ opt: ActiveOption) -> some View {
        HStack {
            Text(opt.closeAction?.rawValue ?? "CLOSED")
                .pillBadge(color: opt.closeAction?.color ?? AppColors.muted)
            Text(opt.contract.displayLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(DesignTokens.Text.secondary))
            Spacer()
            Text(fmtDollar(opt.pnlTotal))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(opt.pnlTotal >= 0 ? AppColors.green : AppColors.red)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .cardStyle()
    }

    private func tradeHistoryRow(_ trade: TradeRecord) -> some View {
        HStack {
            Text(trade.action.rawValue)
                .pillBadge(color: trade.action.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(trade.note)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(DesignTokens.Text.secondary))
                    .lineLimit(1)
                Text(trade.date, style: .date)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(DesignTokens.Text.muted))
            }
            Spacer()
            Text(trade.totalAmount >= 0 ? "+\(fmtDollar(trade.totalAmount))" : fmtDollar(trade.totalAmount))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(trade.totalAmount >= 0 ? AppColors.green : AppColors.red)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .cardStyle()
    }

    // MARK: - Helpers

    private func detailStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(DesignTokens.Text.muted))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func labelValue(_ label: String, _ value: String, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(DesignTokens.Text.muted))
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
