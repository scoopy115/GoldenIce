//
//  GoldenIceBrand.swift
//  Ice
//

import SwiftUI

/// GoldenIce's look: a warm gold that melts into ice blue.
enum GoldenIceBrand {
    static let name = "GoldenIce"

    static let gold = Color(red: 0.90, green: 0.68, blue: 0.20)
    static let paleGold = Color(red: 0.98, green: 0.83, blue: 0.45)
    static let ice = Color(red: 0.55, green: 0.80, blue: 0.95)

    /// The gradient the wordmark and highlights are drawn with.
    static let gradient = LinearGradient(
        colors: [paleGold, gold, ice],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// "GoldenIce", set in the brand gradient.
struct GoldenIceWordmark: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            Text("Golden")
                .foregroundStyle(
                    LinearGradient(
                        colors: [GoldenIceBrand.paleGold, GoldenIceBrand.gold],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Text("Ice")
                .foregroundStyle(
                    LinearGradient(
                        colors: [GoldenIceBrand.ice, GoldenIceBrand.ice.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .font(.system(size: size, weight: .bold, design: .rounded))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(GoldenIceBrand.name)
    }
}

/// A rounded tile with a white glyph, like the ones in System Settings' sidebar.
struct IconTile: View {
    let icon: IconResource
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(
                LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)
            )
            .frame(width: size, height: size)
            .overlay {
                icon.view
                    .foregroundStyle(.white)
                    .padding(size * 0.2)
            }
            .shadow(color: color.opacity(0.25), radius: 1, y: 0.5)
    }
}
