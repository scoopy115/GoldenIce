//
//  IceSlider.swift
//  Ice
//

import SwiftUI

/// A compact slider that displays its value label inside the track.
///
/// This replaces the `CompactSlider` package, which no longer builds
/// against the macOS 27 SDK.
struct IceSlider<Value: BinaryFloatingPoint, ValueLabel: View>: View where Value.Stride: BinaryFloatingPoint {
    @Binding private var value: Value

    @Environment(\.isEnabled) private var isEnabled

    @State private var isHovering = false
    @State private var isDragging = false

    private let bounds: ClosedRange<Value>
    private let step: Value?
    private let valueLabel: ValueLabel

    init(
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value? = nil,
        @ViewBuilder valueLabel: () -> ValueLabel
    ) {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = valueLabel()
    }

    init(
        _ valueLabelKey: LocalizedStringKey,
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value? = nil
    ) where ValueLabel == Text {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = Text(valueLabelKey)
    }

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    private var height: CGFloat {
        if #available(macOS 26.0, *) { 24 } else { 22 }
    }

    private var progress: CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else {
            return 0
        }
        let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
        return CGFloat((clamped - bounds.lowerBound) / span)
    }

    private var progressOpacity: Double {
        isDragging || isHovering ? 0.75 : 0.5
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.primary.opacity(0.075))
                Rectangle()
                    .fill(Color.accentColor.opacity(progressOpacity))
                    .frame(width: geometry.size.width * progress)
                valueLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: geometry.size.width))
        }
        .frame(height: height)
        .saturation(isEnabled ? 1 : 0)
        .opacity(isEnabled ? 1 : 0.5)
        .clipShape(borderShape)
        .contentShape([.interaction, .focusEffect], borderShape)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityAdjustableAction { direction in
            let increment = step ?? (bounds.upperBound - bounds.lowerBound) / 10
            switch direction {
            case .increment:
                updateValue(value + increment)
            case .decrement:
                updateValue(value - increment)
            @unknown default:
                break
            }
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                isDragging = true
                guard width > 0 else {
                    return
                }
                let fraction = min(max(gesture.location.x / width, 0), 1)
                let span = bounds.upperBound - bounds.lowerBound
                updateValue(bounds.lowerBound + Value(fraction) * span)
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    private func updateValue(_ newValue: Value) {
        var newValue = newValue
        if let step, step > 0 {
            let steps = ((newValue - bounds.lowerBound) / step).rounded()
            newValue = bounds.lowerBound + steps * step
        }
        newValue = min(max(newValue, bounds.lowerBound), bounds.upperBound)
        if newValue != value {
            value = newValue
        }
    }
}
