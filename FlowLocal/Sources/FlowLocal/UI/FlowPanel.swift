import AppKit
import SwiftUI

// MARK: - Controller (public API — called by DictationController)

@MainActor
final class FlowPanelController {
    enum PanelState {
        case listening(handsFree: Bool)
        case processing(stage: String)
        case success
        case error(message: String)
    }

    var onCancel: (() -> Void)?
    var onStop: (() -> Void)?

    private let panel: NSPanel
    private let model = FlowPanelModel()
    private var hideGeneration = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 150),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // shadow is drawn in SwiftUI so the clear margins stay clean
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true

        let root = FlowPanelView(
            model: model,
            onCancel: { [weak self] in self?.onCancel?() },
            onStop: { [weak self] in self?.onStop?() }
        )
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 150)
        panel.contentView = host
    }

    func show(_ state: PanelState) {
        hideGeneration += 1
        model.reset(to: state)
        positionBottomCenter()
        panel.orderFrontRegardless()
    }

    func transition(to state: PanelState) {
        model.transition(to: state)
    }

    func updateLevel(_ level: Float) {
        model.push(level: level)
    }

    func updatePartial(_ text: String) {
        model.partial = text
    }

    /// 0 = immediate.
    func hide(after delay: TimeInterval) {
        hideGeneration += 1
        let generation = hideGeneration
        if delay <= 0 {
            panel.orderOut(nil)
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.hideGeneration == generation else { return }
            self.panel.orderOut(nil)
        }
    }

    private func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - panel.frame.width / 2
        let y = frame.minY + 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Model

@MainActor
@Observable
final class FlowPanelModel {
    var state: FlowPanelController.PanelState = .listening(handsFree: false)
    /// Ring buffer of recent mic levels; the waveform scrolls right-to-left.
    var levels: [Float] = Array(repeating: 0, count: FlowPanelModel.barCount)
    var partial: String = ""
    var startedAt = Date()

    static let barCount = 24

    func reset(to state: FlowPanelController.PanelState) {
        self.state = state
        levels = Array(repeating: 0, count: Self.barCount)
        partial = ""
        startedAt = Date()
    }

    func transition(to state: FlowPanelController.PanelState) {
        if UIMotion.reduced {
            self.state = state
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.state = state
            }
        }
    }

    func push(level: Float) {
        levels.removeFirst()
        levels.append(min(max(level, 0), 1))
    }

    var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    var isHandsFree: Bool {
        if case .listening(let handsFree) = state { return handsFree }
        return false
    }
}

/// Reduce-motion check shared by the UI layer.
enum UIMotion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

// MARK: - Views

private struct FlowPanelView: View {
    var model: FlowPanelModel
    var onCancel: () -> Void
    var onStop: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            pill
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .environment(\.colorScheme, .dark) // the bar is a dark HUD in both appearances
    }

    private var pill: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                PanelRoundButton(
                    symbol: "xmark",
                    label: "Cancel dictation",
                    help: "Cancel (Esc)",
                    action: onCancel
                )

                centerContent
                    .frame(maxWidth: .infinity)

                if model.isHandsFree, model.isListening {
                    PanelRoundButton(
                        symbol: "stop.fill",
                        label: "Stop hands-free dictation",
                        help: "Stop and transcribe",
                        action: onStop
                    )
                } else {
                    // Keeps the layout symmetric without a second control.
                    Color.clear.frame(width: 26, height: 26)
                        .accessibilityHidden(true)
                }
            }

            if model.isListening, !model.partial.isEmpty, Prefs.showPartialTranscript {
                Text(model.partial)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
                    .accessibilityLabel("Partial transcript: \(model.partial)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        .animation(UIMotion.reduced ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: model.partial.isEmpty)
    }

    @ViewBuilder
    private var centerContent: some View {
        switch model.state {
        case .listening(let handsFree):
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                WaveformView(levels: model.levels, dimmed: false)
                Text(model.startedAt, style: .timer)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(handsFree ? "Hands-free" : "Listening")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(handsFree ? Color.orange : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(handsFree ? "Hands-free dictation in progress" : "Listening")

        case .processing(let stage):
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                WaveformView(levels: model.levels, dimmed: true)
                Text(stage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Processing: \(stage)")

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.green)
                .transition(UIMotion.reduced ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                .accessibilityLabel("Inserted")

        case .error(let message):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                Button("Copy") {
                    // ponytail: on error, copy whatever text we have so the dictation isn't lost.
                    let text = model.partial.isEmpty ? message : model.partial
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Copy transcript to clipboard")
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// ~24 vertical rounded bars driven by the scrolling level ring buffer.
private struct WaveformView: View {
    let levels: [Float]
    let dimmed: Bool

    private static let maxHeight: CGFloat = 26
    private static let minHeight: CGFloat = 3
    /// Fixed per-bar gain so bars respond unevenly, like a real visualizer.
    private static let gains: [CGFloat] = (0..<FlowPanelModel.barCount).map { i in
        // Deterministic pseudo-random in 0.55...1.35, center-weighted.
        let r = CGFloat(abs(sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1))
        let centerBoost = 1 - abs(CGFloat(i) - CGFloat(FlowPanelModel.barCount - 1) / 2) / CGFloat(FlowPanelModel.barCount)
        return (0.55 + r * 0.8) * (0.7 + 0.6 * centerBoost)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<FlowPanelModel.barCount, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(dimmed ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                    .frame(width: 3, height: height(at: i))
            }
        }
        .frame(height: Self.maxHeight)
        .animation(
            UIMotion.reduced || dimmed ? nil : .spring(response: 0.22, dampingFraction: 0.55),
            value: levels
        )
        .accessibilityLabel("Microphone level indicator")
        .accessibilityHidden(dimmed)
    }

    private func height(at i: Int) -> CGFloat {
        let level = CGFloat(levels[i])
        // Perceptual-ish curve so quiet speech still moves the bars.
        let shaped = pow(level, 0.7) * Self.gains[i]
        return max(Self.minHeight, min(Self.maxHeight, shaped * Self.maxHeight))
    }
}

/// Small circular hover-highlighting button used at the pill's edges.
private struct PanelRoundButton: View {
    let symbol: String
    let label: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.18 : 0.07)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(label)
    }
}
