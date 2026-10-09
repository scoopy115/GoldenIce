//
//  PositionWeights27.swift
//  Ice
//

/// Picks weights for MenuBarAgent's table of item positions on macOS 27.
///
/// MenuBarAgent orders the items on the bar by an integer weight per item, kept in its
/// `TrailingItemPreferredPositions` table. Only the order of the weights matters; on the bars
/// measured, a higher weight sits further left. An item is moved by giving it a weight between
/// those of its new neighbours (the approach Thaw takes, documented in its open source).
enum PositionWeights27 {
    /// The step between weights when an item has a neighbour on one side only.
    static let spacing = 100

    /// How far either side of the ideal weight a free one is looked for.
    static let searchRadius = 64

    /// A weight that places an item between two neighbours.
    ///
    /// - Parameters:
    ///   - left: The weight of the item that is to be on its left, if any.
    ///   - right: The weight of the item that is to be on its right, if any.
    ///   - higherIsLeft: Whether a higher weight sits further left on the bar.
    ///   - taken: Weights other items already have.
    /// - Returns: The weight, or `nil` when the neighbours leave no room between them, or
    ///   are in the wrong order, and the stretch would have to be respaced first.
    static func weight(left: Int?, right: Int?, higherIsLeft: Bool, taken: Set<Int>) -> Int? {
        switch (left, right) {
        case let (left?, right?):
            guard higherIsLeft ? left > right : left < right else {
                return nil
            }
            let low = min(left, right)
            let high = max(left, right)
            guard high - low >= 2 else {
                return nil
            }
            return firstFree(from: low + (high - low) / 2, taken: taken) { $0 > low && $0 < high }
        case let (left?, nil):
            let ideal = higherIsLeft ? left - spacing : left + spacing
            return firstFree(from: ideal, taken: taken) { higherIsLeft ? $0 < left : $0 > left }
        case let (nil, right?):
            let ideal = higherIsLeft ? right + spacing : right - spacing
            return firstFree(from: ideal, taken: taken) { higherIsLeft ? $0 > right : $0 < right }
        case (nil, nil):
            return nil
        }
    }

    /// Whether a weight already places an item between its neighbours, so nothing needs writing.
    static func isInPlace(_ weight: Int, left: Int?, right: Int?, higherIsLeft: Bool) -> Bool {
        let leftOK = left.map { higherIsLeft ? weight < $0 : weight > $0 } ?? true
        let rightOK = right.map { higherIsLeft ? weight > $0 : weight < $0 } ?? true
        return leftOK && rightOK
    }

    /// Whether a higher weight sits further left, judged from items whose weights and positions
    /// are both known; `nil` when they say nothing either way.
    static func higherIsLeft(samples: [(weight: Int, x: Double)]) -> Bool? {
        var votes = 0
        let sorted = samples.sorted { $0.x < $1.x }
        for (a, b) in zip(sorted, sorted.dropFirst()) where a.weight != b.weight {
            votes += a.weight > b.weight ? 1 : -1
        }
        return votes == 0 ? nil : votes > 0
    }

    private static func firstFree(from ideal: Int, taken: Set<Int>, isAllowed: (Int) -> Bool) -> Int? {
        for distance in 0...searchRadius {
            for candidate in distance == 0 ? [ideal] : [ideal + distance, ideal - distance]
            where isAllowed(candidate) && !taken.contains(candidate) {
                return candidate
            }
        }
        return nil
    }
}
