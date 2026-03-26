// WatchlistView.swift — Position list with wheel status
// DHCbot-style list rows with dark theme, sector-organized

import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var store: ThetaStore
    @EnvironmentObject var config: ThetaConfig

    @State private var showAddSheet = false
    @State private var showHelp = false
    @State private var selectedPosition: WheelPosition?
    @State private var sortOption: PositionSort = .sector
    @State private var sortAscending = true

    private var sortedPositions: [WheelPosition] {
        let sorted: [WheelPosition]
        switch sortOption {
        case .symbol:
            sorted = store.positions.sorted { $0.symbol < $1.symbol }
        case .sector:
            sorted = store.positions.sorted {
                if $0.sector == $1.sector { return $0.symbol < $1.symbol }
                return $0.sector < $1.sector
            }
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
                headerBar
                sortHeaders

                if store.positions.isEmpty {
                    emptyState
                } else {
                    positionList
                }
            }
        }
        .sheet(isPresented: $showAddSheet) { AddSymbolSheet() }
        .sheet(isPresented: $showHelp) { HelpSheet(screen: .positions) }
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

            Button { showHelp = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.gold)
            }

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
            ForEach(PositionSort.allCases, id: \.self) { opt in
                sortButton(opt.rawValue, selected: sortOption == opt) {
                    if sortOption == opt { sortAscending.toggle() }
                    else { sortOption = opt; sortAscending = true }
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func sortButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: selected ? .bold : .medium))
                if selected {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundColor(.white.opacity(selected ? DesignTokens.Text.secondary : DesignTokens.Text.muted))
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Position List

    private var positionList: some View {
        List {
            // When sorting by sector, show section headers
            if sortOption == .sector {
                let grouped = Dictionary(grouping: sortedPositions, by: { $0.sector })
                let sectors = grouped.keys.sorted()
                ForEach(sortAscending ? sectors : sectors.reversed(), id: \.self) { sector in
                    Section {
                        ForEach(grouped[sector] ?? []) { position in
                            positionRowView(position)
                        }
                        .onDelete { offsets in
                            for idx in offsets {
                                if let sym = grouped[sector]?[idx].symbol {
                                    store.removeSymbol(sym)
                                }
                            }
                        }
                    } header: {
                        sectorHeader(sector)
                    }
                }
            } else {
                ForEach(sortedPositions) { position in
                    positionRowView(position)
                }
                .onDelete(perform: deletePositions)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.refreshPrices() }
    }

    private func positionRowView(_ position: WheelPosition) -> some View {
        PositionRow(position: position)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .contentShape(Rectangle())
            .onTapGesture { selectedPosition = position }
    }

    private func sectorHeader(_ sector: Sector) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(sector.color)
                .frame(width: 3, height: 12)
            Text(sector.rawValue.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(sector.color)
        }
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

                    Text(position.sector.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(position.sector.color)

                    if position.shares > 0 {
                        Text("\(position.shares)sh")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(AppColors.cyan)
                    }
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
    @State private var recSort: RecommendationSort = .iv
    @State private var recSortAsc = false  // IV defaults descending (highest first)

    private var sortedSuggestions: [IVCandidate] {
        let sorted: [IVCandidate]
        switch recSort {
        case .symbol:
            sorted = suggestions.sorted { $0.symbol < $1.symbol }
        case .sector:
            sorted = suggestions.sorted {
                if $0.sector == $1.sector { return $0.symbol < $1.symbol }
                return $0.sector < $1.sector
            }
        case .iv:
            sorted = suggestions.sorted { $0.iv > $1.iv }
        case .yield:
            sorted = suggestions.sorted { $0.premiumYield > $1.premiumYield }
        }
        return recSortAsc ? sorted : sorted.reversed()
    }

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
            // Header row
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
                    // Full scan button
                    Button {
                        Task { await fullScan() }
                    } label: {
                        Text("All")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.gold)
                    }
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

            // Sort headers for recommendations
            recSortHeaders

            if suggestions.isEmpty && !isScanning {
                Text("Tap refresh to scan for high-IV candidates")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(DesignTokens.Text.muted))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else if recSort == .sector {
                // Grouped by sector
                let grouped = Dictionary(grouping: sortedSuggestions, by: { $0.sector })
                let sectors = grouped.keys.sorted()
                ForEach(sectors, id: \.self) { sector in
                    sectorGroupHeader(sector)
                    ForEach(grouped[sector] ?? []) { candidate in
                        suggestionRow(candidate)
                    }
                }
            } else {
                ForEach(sortedSuggestions) { candidate in
                    suggestionRow(candidate)
                }
            }
        }
    }

    // MARK: - Recommendation Sort Headers

    private var recSortHeaders: some View {
        HStack(spacing: 0) {
            ForEach(RecommendationSort.allCases, id: \.self) { opt in
                recSortButton(opt)
            }
            Spacer()
        }
    }

    private func recSortButton(_ opt: RecommendationSort) -> some View {
        let selected = recSort == opt
        return Button {
            if recSort == opt { recSortAsc.toggle() }
            else {
                recSort = opt
                // Default descending for IV and Yield, ascending for Name and Sector
                recSortAsc = (opt == .symbol || opt == .sector)
            }
        } label: {
            HStack(spacing: 2) {
                Text(opt.rawValue)
                    .font(.system(size: 10, weight: selected ? .bold : .medium))
                if selected {
                    Image(systemName: recSortAsc ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundColor(.white.opacity(selected ? DesignTokens.Text.secondary : DesignTokens.Text.muted))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
    }

    private func sectorGroupHeader(_ sector: Sector) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(sector.color)
                .frame(width: 3, height: 12)
            Text(sector.rawValue.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(sector.color)
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Suggestion Row

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

                // Symbol + sector
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.symbol)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(alreadyAdded ? .white.opacity(0.3) : .white)
                    Text(candidate.sector.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(candidate.sector.color)
                }
                .frame(width: 55, alignment: .leading)

                // Price
                Text(fmtPrice(candidate.price))
                    .font(.system(size: 11, design: .monospaced))
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
            .frame(width: 4, height: 32)
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
        suggestions = await IVScanner.shared.quickScan()
    }

    private func fullScan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        suggestions = await IVScanner.shared.scanHighIV()
    }
}
