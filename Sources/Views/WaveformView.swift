import SwiftUI

/// Animated waveform visualization using Canvas drawing.
/// Adapts its appearance based on the current voice state.
struct WaveformView: View {
    let state: VoiceState
    let micLevel: Float
    let outputLevel: Float

    @State private var phase: Double = 0
    @State private var animationTimer: Timer?

    private var activeLevel: Double {
        switch state {
        case .listening: return Double(max(micLevel, 0.05))
        case .speaking: return Double(max(outputLevel, 0.1))
        case .thinking: return 0.3
        case .idle: return 0.0
        }
    }

    private var waveColor: Color {
        switch state {
        case .idle: return .secondary.opacity(0.3)
        case .listening: return .blue
        case .thinking: return .purple
        case .speaking: return .green
        }
    }

    var body: some View {
        Canvas { context, size in
            let midY: Double = Double(size.height) / 2.0
            let width: Double = Double(size.width)
            let amplitude: Double = midY * activeLevel * 0.8

            // Draw multiple wave layers for depth
            for layer in 0..<3 {
                let layerOpacity: Double = 1.0 - Double(layer) * 0.3
                let layerPhase: Double = phase + Double(layer) * 0.5
                let layerAmp: Double = amplitude * (1.0 - Double(layer) * 0.2)

                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))

                for x in stride(from: 0.0, through: Double(width), by: 2.0) {
                    let normalizedX: Double = x / Double(width)
                    // Combine multiple sine waves for organic feel
                    let wave1: Double = sin(normalizedX * .pi * 4.0 + layerPhase * 3.0)
                    let wave2: Double = sin(normalizedX * .pi * 6.0 + layerPhase * 2.0) * 0.5
                    let wave3: Double = sin(normalizedX * .pi * 2.0 + layerPhase * 1.5) * 0.3

                    // Envelope: taper at edges
                    let envelope: Double = sin(normalizedX * .pi)

                    let y = Double(midY) + (wave1 + wave2 + wave3) * layerAmp * envelope
                    path.addLine(to: CGPoint(x: x, y: y))
                }

                context.stroke(
                    path,
                    with: .color(waveColor.opacity(layerOpacity)),
                    lineWidth: 2.0 - Double(layer) * 0.5
                )
            }
        }
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            animationTimer?.invalidate()
        }
        .onChange(of: state) { _, _ in
            startAnimation()
        }
    }

    private func startAnimation() {
        animationTimer?.invalidate()
        guard state != .idle else { return }

        // Use a display-link-like timer for smooth animation
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor in
                phase += 0.05
            }
        }
    }
}

/// Circular pulsing indicator for the current state.
struct StateIndicator: View {
    let state: VoiceState
    let level: Float

    @State private var isPulsing = false

    private var indicatorColor: Color {
        switch state {
        case .idle: return .secondary
        case .listening: return .blue
        case .thinking: return .purple
        case .speaking: return .green
        }
    }

    var body: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                state == .idle
                    ? .default
                    : .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onChange(of: state, initial: true) { _, newState in
                isPulsing = newState != .idle
            }
    }
}
