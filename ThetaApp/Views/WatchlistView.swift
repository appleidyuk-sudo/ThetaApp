// WatchlistView.swift — Position list with wheel status
// DHCbot-style list rows with dark theme

import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var store: ThetaStore
    @EnvironmentObject var config: ThetaConfig

    @State private var showAddSheet = false
    @State private var selectedPosition: WheelPosition?
    @State private var sortOption: SortOption = .symbol
    @State private var sortAscending = true

    private var sortedPositions: [WheelPosition] {
        let sorted: [WheelPosition]
        switch sortOption {
        case .symbol:
            sorted = store.positions.sorted { $0.symbol < $1.symbol }
        case .phase:
            sorted = store.positions.sorted { $0.phase.rawValue < $1.phase.rawValue }
        case .pnl:
            sorted = store.positions.sorted { $0.totalPremiumCollected > $1.totalPremiumCollected }
        case .dte:
            sorted = store.positions.sorted {
                ($0.currentActiveOption?.dte ?? 999) < ($1.currentActiveOption?.dte ?? 999)
            }
        }
        return sortAscending ? sorted : sorted.reversed()
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                // Header
                headerBar

                // Sort headers
                sortHeaders

                // Position list
                if store.positions.isEmpty {
                    emptyState
                } else {
                    positionList
                }
            }
        }
        .sheet(isPresented: $showAddSheet) { AddSymbolSheet() }
        .sheet(item: $selectedPosition) { pos in
            PositionDetailView(position: pos)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("Positions")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Button { showAddSheet = true } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppColors.gold)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Sort Headers

    private var sortHeaders: some View {
        HStack(spacing: 0) {
            sortHeaderButton("SYMBOL", option: .symbol)
            sortHeaderButton("PHASE", option: .phase)
            Spacer()
            sortHeaderButton("DTE", option: .dte)
            sortHeaderButton("P&L", option: .pnl)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func sortHeaderButton(_ label: String, option: SortOption) -> some View {
        Button {
            if sortOption == option {
                sortAscending.toggle()
            } else {
                sortOption = option
                sortAscending = true
            }
        } label: {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: sortOption == option ? .bold : .medium))
                if sortOption == option {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundColor(.white.opacity(sortOption == option ? DesignTokens.Text.secondary : DesignTokens.Text.muted))
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Position List

    private var positionList: some View {
        List {
            ForEach(sortedPositions) { position in
                PositionRow(position: position)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedPosition = position }
            }
            .onDelete(perform: deletePositions)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.refreshPrices() }
    }

    private func deletePositions(at offsets: IndexSet) {
        for index in offsets {
            let symbol = sortedPositions[index].symbol
            store.removeSymbol(symbol)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.15))
            Text("No positions")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(DesignTokens.Text.muted))
            Text("Tap + to add symbols and start The Wheel")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(DesignTokens.Text.faint))
            Spacer()
        }
    }
}

// MARK: - Position Row

struct PositionRow: View {
    let position: WheelPosition

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: DesignTokens.Spacing.sm) {
                // Phase icon
                Image(systemName: position.phase.icon)
                    .foregroundColor(position.phase.color)
                    .font(.system(size: 18))
                    .frame(width: 24)

                // Symbol + info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(position.symbol)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)

                        Text(position.phase.shortLabel)
                            .pillBadge(color: position.phase.color)

                        if position.shares > 0 {
                            Text("\(position.shares)sh")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(AppColors.cyan)
                        }

                        Text("\(Int(position.weight * 100))%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    }

                    // Active option info
                    if let opt = position.currentActiveOption {
                        HStack(spacing: 8) {
                            Text(opt.contract.displayLabel)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(opt.contract.optionType.color)

                            Text("δ\(fmtDelta(opt.contract.delta))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(DesignTokens.Text.tertiary))

                            Text(fmtDTE(opt.dte))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(opt.dte <= 15 ? AppColors.red : AppColors.yellow)
                        }
                    }
                }

                Spacer()

                // Price + P&L column
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmtPrice(position.currentPrice))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)

                    if let opt = position.currentActiveOption {
                        let pnl = opt.pnlTotal
                        Text(pnl >= 0 ? "+\(fmtDollar(pnl))" : fmtDollar(pnl))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(pnl >= 0 ? AppColors.green : AppColors.red)

                        Text(fmtSignedPct(opt.pnlPercent))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(opt.pnlPercent >= 0 ? AppColors.green : AppColors.red)
                    }
                }

                // Premium collected
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmtDollar(position.totalPremiumCollected))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(AppColors.green)

                    if position.wheelCycleCount > 0 {
                        Text("×\(position.wheelCycleCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.gold)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .cardStyle()
    }
}

// MARK: - Add Symbol Sheet

struct AddSymbolSheet: View {
    @EnvironmentObject var store: ThetaStore
    @Environment(\.dismiss) var dismiss

    @State private var symbol = ""
    @State private var weight = 0.20
    @State private var errorMessage: String?
    @State private var suggestions: [IVCandidate] = []
    @State private var isScanning = false

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.lg) {
                        // Symbol input
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SYMBOL")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(DesignTokens.Text.muted))

                            TextField("AAPL", text: $symbol)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                        }

                        // Weight slider
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("PORTFOLIO WEIGHT")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                                Spacer()
                                Text("\(Int(weight * 100))%")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(AppColors.gold)
                            }

                            Slider(value: $weight, in: 0.05...1.0, step: 0.05)
                                .tint(AppColors.gold)
                        }

                        if let err = errorMessage {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.red)
                        }

                        // High IV Suggestions
                        ivSuggestionsSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Add Symbol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.gold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let sym = symbol.trimmingCharacters(in: .whitespaces).uppercased()
                        guard !sym.isEmpty else {
                            errorMessage = "Enter a symbol"
                            return
                        }
                        store.addSymbol(sym, weight: weight)
                        dismiss()
                    }
                    .foregroundColor(AppColors.green)
                    .bold()
                }
            }
            .task { await loadSuggestions() }
        }
    }

    // MARK: - IV Suggestions Section

    private var ivSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(AppColors.orange)
                    .font(.system(size: 12))
                Text("HIGH IV SUGGESTIONS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                Spacer()
                if isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(AppColors.gold)
                } else {
                    Button {
                        Task { await loadSuggestions() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.gold)
                    }
                }
            }

            Text("Ranked by implied volatility — higher IV = more premium")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(DesignTokens.Text.faint))

            if suggestions.isEmpty && !isScanning {
                Text("Tap refresh to scan for high-IV candidates")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(suggestions) { candidate in
                    suggestionRow(candidate)
                }
            }
        }
    }

    private func suggestionRow(_ candidate: IVCandidate) -> some View {
        let alreadyAdded = store.positions.contains { $0.symbol == candidate.symbol }

        return Button {
            if !alreadyAdded {
                symbol = candidate.symbol
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                // IV rank bar
                ivRankIndicator(candidate.ivRank)

                // Symbol
                Text(candidate.symbol)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(alreadyAdded ? .white.opacity(0.3) : .white)
                    .frame(width: 50, alignment: .leading)

                // Price
                Text(fmtPrice(candidate.price))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(DesignTokens.Text.secondary))

                Spacer()

                // IV
                VStack(alignment: .trailing, spacing: 1) {
                    Text("IV")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    Text(candidate.ivLabel)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(ivColor(candidate.iv))
                }

                // Premium yield
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Yield")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    Text(candidate.yieldLabel)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.green)
                }

                // Est. 30d premium
                VStack(alignment: .trailing, spacing: 1) {
                    Text("~30d")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    Text(fmtPrice(candidate.premium30d))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppColors.gold)
                }

                // Status
                if alreadyAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.green)
                        .font(.system(size: 14))
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundColor(AppColors.gold)
                        .font(.system(size: 14))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .cardStyle()
        }
        .disabled(alreadyAdded)
    }

    private func ivRankIndicator(_ rank: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(ivColor(rank).opacity(0.8))
            .frame(width: 4, height: 28)
    }

    private func ivColor(_ iv: Double) -> Color {
        if iv > 0.80 { return AppColors.red }
        if iv > 0.50 { return AppColors.orange }
        if iv > 0.30 { return AppColors.yellow }
        return AppColors.green
    }

    // MARK: - Load

    private func loadSuggestions() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        suggestions = await IVScanner.shared.quickScan(limit: 10)
    }
}
