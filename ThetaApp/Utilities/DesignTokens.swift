// DesignTokens.swift — Opacity-based design system from DHCbot

import SwiftUI

enum DesignTokens {
    // MARK: - Text Opacity
    enum Text {
        static let primary:   Double = 1.0
        static let secondary: Double = 0.7
        static let tertiary:  Double = 0.5
        static let muted:     Double = 0.35
        static let faint:     Double = 0.2
    }

    // MARK: - Background Opacity
    enum Background {
        static let card:    Double = 0.06
        static let hover:   Double = 0.08
        static let subtle:  Double = 0.04
        static let overlay: Double = 0.15
        static let heavy:   Double = 0.25
    }

    // MARK: - Border/Stroke Opacity
    enum Border {
        static let light:  Double = 0.08
        static let medium: Double = 0.15
        static let strong: Double = 0.25
    }

    // MARK: - Chart Opacity
    enum Chart {
        static let area:  Double = 0.10
        static let zone:  Double = 0.08
        static let grid:  Double = 0.15
        static let label: Double = 0.4
    }

    // MARK: - Corner Radii
    enum Radius {
        static let small:  CGFloat = 6
        static let medium: CGFloat = 10
        static let large:  CGFloat = 14
        static let pill:   CGFloat = 20
    }

    // MARK: - Spacing
    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
    }
}

// MARK: - View Modifiers

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(DesignTokens.Background.card))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium)
                    .stroke(Color.white.opacity(DesignTokens.Border.light), lineWidth: 0.5)
            )
    }
}

struct PillBadge: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
    func pillBadge(color: Color) -> some View { modifier(PillBadge(color: color)) }
}

// MARK: - Gradient Background

struct AppBackground: View {
    @AppStorage("bgDarkness") private var bgDarkness: Double = 0.85

    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02 * bgDarkness, green: 0.04 * bgDarkness, blue: 0.10 * bgDarkness),
                Color(red: 0.01 * bgDarkness, green: 0.02 * bgDarkness, blue: 0.06 * bgDarkness)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
