import AppKit
import Combine
import SwiftUI

@MainActor
final class KeyPressOverlayController {
    static let shared = KeyPressOverlayController()

    private let model = KeyPressOverlayModel()
    private let panel: NSPanel
    private let hostingView: NSHostingView<KeyPressOverlayView>
    private var hideTask: DispatchWorkItem?

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        hostingView = NSHostingView(rootView: KeyPressOverlayView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 260)
        panel.contentView = hostingView
        panel.orderOut(nil)
    }

    func show(keyLabel: String, heat: Double, comboMessage: String? = nil) {
        guard !keyLabel.isEmpty else { return }

        hideTask?.cancel()
        hideTask = nil
        updatePosition()

        if !panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }

        model.present(text: keyLabel, heat: heat, comboMessage: comboMessage)
        schedulePanelHide()
    }

    func hideImmediately() {
        hideTask?.cancel()
        hideTask = nil
        model.clear()
        panel.orderOut(nil)
    }

    private func schedulePanelHide() {
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.model.entries.isEmpty {
                self.panel.orderOut(nil)
            }
        }

        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: task)
    }

    private func updatePosition() {
        let referencePoint = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(referencePoint) }) ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let size = panel.frame.size
        let x = visibleFrame.maxX - size.width - 24
        let y = visibleFrame.minY + 18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
private final class KeyPressOverlayModel: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let heat: Double
    }

    struct ComboEntry: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let heat: Double
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var comboEntry: ComboEntry?

    func present(text: String, heat: Double, comboMessage: String?) {
        let clampedHeat = min(max(heat, 0), 1)
        entries.append(Entry(text: text, heat: clampedHeat))
        if entries.count > 3 {
            entries.removeFirst(entries.count - 3)
        }

        if let comboMessage, !comboMessage.isEmpty {
            comboEntry = ComboEntry(text: comboMessage, heat: clampedHeat)
        }
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        entries.removeAll()
        comboEntry = nil
    }

    func clearCombo(id: UUID) {
        guard comboEntry?.id == id else { return }
        comboEntry = nil
    }
}

private struct KeyPressOverlayView: View {
    @ObservedObject var model: KeyPressOverlayModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let comboEntry = model.comboEntry {
                ComboCalloutView(entry: comboEntry) {
                    model.clearCombo(id: comboEntry.id)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 18)
                .padding(.trailing, 8)
            }

            ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                FlameKeyText(
                    entry: entry,
                    stackIndex: model.entries.count - index - 1
                ) {
                    model.remove(entry)
                }
            }
        }
        .frame(width: 360, height: 260, alignment: .bottomTrailing)
        .padding(.trailing, 10)
        .padding(.bottom, 6)
        .background(Color.clear)
        .compositingGroup()
    }
}

private struct FlameKeyText: View {
    let entry: KeyPressOverlayModel.Entry
    let stackIndex: Int
    let onFinished: () -> Void

    @State private var yOffset: CGFloat = 0
    @State private var xOffset: CGFloat = 0
    @State private var opacity = 0.0
    @State private var scale = 0.92
    @State private var pulse = 0.0
    @State private var emberLift: CGFloat = 0
    @State private var emberSpread: CGFloat = 0

    var body: some View {
        let metrics = flameMetrics

        ZStack(alignment: .bottomTrailing) {
            if stackIndex == 0 {
                EmberTrail(
                    heat: entry.heat,
                    progress: opacity,
                    lift: emberLift,
                    spread: emberSpread
                )
                .offset(x: xOffset * 0.38, y: yOffset - 1)
            }

            if stackIndex == 0 {
                Text(entry.text)
                    .font(.system(size: metrics.fontSize + 8, weight: .black, design: .rounded))
                    .italic()
                    .kerning(0.8)
                    .foregroundStyle(trailGradient)
                    .blur(radius: 7 + (pulse * 3.5))
                    .scaleEffect(scale * (1.08 + (pulse * 0.05)))
                    .opacity(opacity * (0.28 + (pulse * 0.18)))
                    .offset(x: xOffset * 0.3, y: yOffset + 6)
            }

            Text(entry.text)
                .font(.system(size: metrics.fontSize, weight: .heavy, design: .rounded))
                .italic()
                .kerning(0.4)
                .foregroundStyle(fireGradient)
                .shadow(color: metrics.glow.opacity(0.34 + (pulse * 0.16)), radius: 14 + (entry.heat * 10) + (pulse * 8), x: 0, y: 0)
                .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 8)
                .scaleEffect(scale * (1 + (pulse * 0.025)))
                .opacity(opacity)
                .offset(x: xOffset * 0.46, y: yOffset + 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(false)
        .onAppear {
            let drift = flameDrift

            opacity = 0
            scale = 0.92
            pulse = 0
            emberLift = 0
            emberSpread = 0
            xOffset = drift.initialX
            yOffset = metrics.initialOffset

            withAnimation(.easeOut(duration: 0.14)) {
                opacity = metrics.baseOpacity
                scale = 1.0
                xOffset = drift.settledX
                yOffset = metrics.settledOffset
            }

            if stackIndex == 0 {
                withAnimation(
                    .easeInOut(duration: 0.34 - (entry.heat * 0.12))
                    .repeatForever(autoreverses: true)
                ) {
                    pulse = 1
                }

                withAnimation(.easeOut(duration: metrics.flightDuration + 0.12)) {
                    emberLift = 1
                    emberSpread = 1
                }
            }

            withAnimation(.easeOut(duration: metrics.flightDuration).delay(0.08)) {
                opacity = 0
                scale = 1.08
                xOffset = drift.finalX
                yOffset = metrics.finalOffset
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + metrics.flightDuration + 0.18) {
                onFinished()
            }
        }
    }

    private var fireGradient: LinearGradient {
        let colors: [Color]

        switch entry.heat {
        case 0.75...:
            colors = [
                Color(red: 1.00, green: 0.98, blue: 0.82),
                Color(red: 1.00, green: 0.79, blue: 0.29),
                Color(red: 1.00, green: 0.45, blue: 0.14),
                Color(red: 0.84, green: 0.14, blue: 0.08)
            ]
        case 0.45...:
            colors = [
                Color(red: 1.00, green: 0.97, blue: 0.88),
                Color(red: 1.00, green: 0.83, blue: 0.42),
                Color(red: 1.00, green: 0.59, blue: 0.20)
            ]
        default:
            colors = [
                Color.white.opacity(0.96),
                Color(red: 1.00, green: 0.88, blue: 0.58)
            ]
        }

        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var trailGradient: LinearGradient {
        let colors: [Color] = [
            Color(red: 1.0, green: 0.94, blue: 0.7).opacity(0.95),
            Color(red: 1.0, green: 0.58, blue: 0.16).opacity(0.72),
            Color(red: 0.86, green: 0.16, blue: 0.08).opacity(0.0)
        ]

        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var flameMetrics: (fontSize: CGFloat, initialOffset: CGFloat, settledOffset: CGFloat, finalOffset: CGFloat, flightDuration: Double, baseOpacity: Double, glow: Color) {
        let size = max(24, 50 - CGFloat(stackIndex * 7))
        let settled = CGFloat(stackIndex * -30)
        let final = settled - CGFloat(62 + (entry.heat * 46))
        let duration = 0.78 - (entry.heat * 0.18)
        let opacity = max(0.38, 0.92 - Double(stackIndex) * 0.16)
        let glow = Color(red: 1.0, green: 0.45 + (entry.heat * 0.2), blue: 0.12)

        return (
            fontSize: size,
            initialOffset: 18,
            settledOffset: settled,
            finalOffset: final,
            flightDuration: duration,
            baseOpacity: opacity,
            glow: glow
        )
    }

    private var flameDrift: (initialX: CGFloat, settledX: CGFloat, finalX: CGFloat) {
        let hash = abs(entry.id.hashValue)
        let direction: CGFloat = hash.isMultiple(of: 2) ? -1 : 1
        let base = CGFloat((hash % 9) + 4) * direction
        let swing = CGFloat((hash % 7) + 10) * direction

        return (
            initialX: base * 0.35,
            settledX: base,
            finalX: swing
        )
    }
}

private struct EmberTrail: View {
    let heat: Double
    let progress: Double
    let lift: CGFloat
    let spread: CGFloat

    private let emberOffsets: [CGSize] = [
        CGSize(width: -4, height: -2),
        CGSize(width: 7, height: -12),
        CGSize(width: -11, height: -18),
        CGSize(width: 14, height: -24),
        CGSize(width: 1, height: -30)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ForEach(Array(emberOffsets.enumerated()), id: \.offset) { index, offset in
                Circle()
                    .fill(emberColor(for: index))
                    .frame(width: emberSize(for: index), height: emberSize(for: index))
                    .blur(radius: 1.4 + (heat * 1.8))
                    .opacity(max(0, (progress * 0.5) - Double(index) * 0.05))
                    .offset(
                        x: offset.width + emberXDrift(for: index),
                        y: offset.height - (lift * emberYTravel(for: index))
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func emberColor(for index: Int) -> Color {
        if heat > 0.72 {
            return index.isMultiple(of: 2)
                ? Color(red: 1.0, green: 0.86, blue: 0.42)
                : Color(red: 1.0, green: 0.44, blue: 0.14)
        }

        return index.isMultiple(of: 2)
            ? Color(red: 1.0, green: 0.92, blue: 0.62)
            : Color(red: 1.0, green: 0.62, blue: 0.22)
    }

    private func emberSize(for index: Int) -> CGFloat {
        max(3, 7 - CGFloat(index))
    }

    private func emberYTravel(for index: Int) -> CGFloat {
        CGFloat(18 + (index * 8)) + CGFloat(heat * 16)
    }

    private func emberXDrift(for index: Int) -> CGFloat {
        let direction: CGFloat = index.isMultiple(of: 2) ? -1 : 1
        return direction * spread * CGFloat(4 + index * 3)
    }
}

private struct ComboCalloutView: View {
    let entry: KeyPressOverlayModel.ComboEntry
    let onFinished: () -> Void

    @State private var opacity = 0.0
    @State private var scale = 0.82
    @State private var yOffset: CGFloat = 18

    var body: some View {
        Text(entry.text.uppercased())
            .font(.system(size: 22, weight: .black, design: .rounded))
            .italic()
            .kerning(1.3)
            .foregroundStyle(comboGradient)
            .shadow(color: Color.black.opacity(0.75), radius: 0, x: 2, y: 2)
            .shadow(color: comboGlow.opacity(0.65), radius: 16, x: 0, y: 0)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(y: yOffset)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.interpolatingSpring(stiffness: 220, damping: 16)) {
                    opacity = 1
                    scale = 1
                    yOffset = 0
                }

                withAnimation(.easeIn(duration: 0.36).delay(0.78)) {
                    opacity = 0
                    scale = 1.06
                    yOffset = -18
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.18) {
                    onFinished()
                }
            }
    }

    private var comboGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.99, blue: 0.84),
                Color(red: 1.0, green: 0.82, blue: 0.24),
                Color(red: 1.0, green: 0.36, blue: 0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var comboGlow: Color {
        Color(
            red: 1.0,
            green: 0.5 + (entry.heat * 0.18),
            blue: 0.08
        )
    }
}
