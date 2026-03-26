// SettingsView.swift — Configuration knobs for The Wheel strategy
// Maps to thetagang.toml sections

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ThetaStore
    @EnvironmentObject var config: ThetaConfig

    @State private var showResetConfirm = false
    @State private var showHelp = false

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                // Header bar
                HStack {
                    Text("Settings")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Button { showHelp = true } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.gold)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

            List {
                // Account
                Section {
                    sliderRow("Starting Cash", value: $config.startingCash,
                              range: 10_000...1_000_000, step: 10_000,
                              format: { fmtDollar($0) })
                    sliderRow("Margin Usage", value: $config.marginUsage,
                              range: 0.1...1.0, step: 0.05,
                              format: { fmtPct($0) })
                } header: {
                    sectionHeader("ACCOUNT")
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))

                // Target
                Section {
                    sliderRow("Target Delta", value: $config.targetDelta,
                              range: 0.05...0.50, step: 0.05,
                              format: { fmtDelta($0) })
                    stepperRow("Target DTE", value: $config.targetDTE, range: 7...90)
                    stepperRow("Max DTE", value: $config.maxDTE, range: 30...365)
                    stepperRow("Min Open Interest", value: $config.minOpenInterest, range: 0...100)
                    sliderRow("Min Credit", value: $config.minimumCredit,
                              range: 0.01...1.00, step: 0.01,
                              format: { fmtPrice($0) })
                } header: {
                    sectionHeader("TARGET")
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))

                // Roll When
                Section {
                    sliderRow("P&L Target", value: $config.rollPnlTarget,
                              range: 0.50...1.00, step: 0.05,
                              format: { fmtPct($0) })
                    stepperRow("DTE Trigger", value: $config.rollDTE, range: 1...30)
                    sliderRow("Min P&L for DTE Roll", value: $config.rollMinPnl,
                              range: -1.0...0.5, step: 0.05,
                              format: { fmtSignedPct($0) })
                    toggleRow("Roll Puts ITM", isOn: $config.rollPutsITM)
                    toggleRow("Roll Calls ITM", isOn: $config.rollCallsITM)
                    toggleRow("Credit Only", isOn: $config.rollCreditOnly)
                    toggleRow("Maintain High Water Mark", isOn: $config.maintainHighWaterMark)
                } header: {
                    sectionHeader("ROLL WHEN")
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))

                // Write When
                Section {
                    toggleRow("Puts on Red Days", isOn: $config.writePutsOnRed)
                    toggleRow("Calls on Green Days", isOn: $config.writeCallsOnGreen)
                    sliderRow("Call Cap Factor", value: $config.callCapFactor,
                              range: 0.0...1.0, step: 0.1,
                              format: { fmtPct($0) })
                    sliderRow("Max New Contracts %", value: $config.maxNewContractsPct,
                              range: 0.01...0.20, step: 0.01,
                              format: { fmtPct($0) })
                } header: {
                    sectionHeader("WRITE WHEN")
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))

                // Write Threshold
                Section {
                    sliderRow("Price Change Threshold", value: $config.writeThreshold,
                              range: 0.0...0.05, step: 0.005,
                              format: { fmtPct($0) })
                    sliderRow("Sigma Threshold", value: $config.writeThresholdSigma,
                              range: 0.0...3.0, step: 0.1,
                              format: { String(format: "%.1fσ", $0) })
                    stepperRow("Std Dev Window", value: $config.dailyStddevWindow, range: 5...90)
                } header: {
                    sectionHeader("WRITE THRESHOLD")
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))

                // VIX Hedging
                Section {
                    toggleRow("VIX Hedging", isOn: $config.vixHedgeEnabled)
                    if config.vixHedgeEnabled {
                        sliderRow("VIX Hedge Delta", value: $config.vixHedgeDelta,
                                  range: 0.10...0.50, step: 0.05,
                                  format: { fmtDelta($0) })
                        stepperRow("VIX Hedge DTE", value: $config.vixHedgeDTE, range: 7...90)
                        sliderRow("VIX Allocation", value: $config.vixHedgeAllocation,
                                  range: 0.005...0.05, step: 0.005,
                                  format: { fmtPct($0) })
                        sliderRow("Close Above VIX", value: $config.vixCloseAbove,
                                  range: 20...80, step: 5,
                                  format: { String(format: "%.0f", $0) })
                    }
                } header: {
                    sectionHeader("VIX HEDGING")
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))

                // Cash Management
                Section {
                    toggleRow("Cash Management", isOn: $config.cashMgmtEnabled)
                    if config.cashMgmtEnabled {
                        HStack {
                            Text("Fund")
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                            Spacer()
                            TextField("SGOV", text: $config.cashMgmtFund)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(AppColors.gold)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        sliderRow("Buy Threshold", value: $config.cashBuyThreshold,
                                  range: 0.005...0.05, step: 0.005,
                                  format: { fmtPct($0) })
                        sliderRow("Sell Threshold", value: $config.cashSellThreshold,
                                  range: 0.001...0.02, step: 0.001,
                                  format: { fmtPct($0) })
                    }
                } header: {
                    sectionHeader("CASH MANAGEMENT")
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))

                // Regime Rebalance
                Section {
                    toggleRow("Regime Rebalance", isOn: $config.regimeEnabled)
                    if config.regimeEnabled {
                        stepperRow("Lookback Days", value: $config.regimeLookbackDays, range: 10...120)
                        sliderRow("Soft Band", value: $config.regimeSoftBand,
                                  range: 0.10...0.50, step: 0.05,
                                  format: { fmtPct($0) })
                        sliderRow("Hard Band", value: $config.regimeHardBand,
                                  range: 0.25...1.00, step: 0.05,
                                  format: { fmtPct($0) })
                    }
                } header: {
                    sectionHeader("REGIME REBALANCE")
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))

                // Execution
                Section {
                    stepperRow("Refresh Interval (min)", value: $config.refreshInterval, range: 1...60)
                    toggleRow("Auto Execute", isOn: $config.autoExecute)
                } header: {
                    sectionHeader("EXECUTION")
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))

                // Display
                Section {
                    sliderRow("Background Darkness", value: $config.bgDarkness,
                              range: 0.0...1.0, step: 0.05,
                              format: { String(format: "%.0f%%", $0 * 100) })
                } header: {
                    sectionHeader("DISPLAY")
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))

                // Reset
                Section {
                    Button {
                        showResetConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Reset Simulation")
                        }
                        .foregroundColor(AppColors.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .listRowBackground(Color.white.opacity(DesignTokens.Background.card))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            } // end VStack
        }
        .sheet(isPresented: $showHelp) { HelpSheet(screen: .settings) }
        .alert("Reset Simulation?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                store.resetSimulation()
            }
        } message: {
            Text("This will clear all positions, trades, and reset cash to starting amount.")
        }
    }

    // MARK: - Row Builders

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white.opacity(DesignTokens.Text.muted))
    }

    private func sliderRow(_ label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double,
                           format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.gold)
            }
            Slider(value: value, in: range, step: step)
                .tint(AppColors.gold)
        }
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white)
            Spacer()
            Text("\(value.wrappedValue)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(AppColors.gold)
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white)
        }
        .tint(AppColors.gold)
    }
}
