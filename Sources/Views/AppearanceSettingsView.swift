import SwiftUI

/// Settings view for customizing the visual appearance of QuinnVoice.
///
/// Includes theme selection, accent color picker, waveform style, panel opacity,
/// and animation speed controls with a live waveform preview.
struct AppearanceSettingsView: View {
    @Bindable var configManager: ConfigManager
    @State private var previewPhase: Double = 0
    @State private var previewTimer: Timer?

    var body: some View {
        Form {
            // Theme
            Section("Theme") {
                Picker("Appearance", selection: $configManager.config.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Label(theme.displayName, systemImage: theme.iconName)
                            .tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: configManager.config.theme) { _, _ in
                    configManager.save()
                }
            }

            // Accent Color
            Section("Accent Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(AccentColorChoice.allCases, id: \.self) { choice in
                        AccentColorButton(
                            choice: choice,
                            isSelected: configManager.config.accentColor == choice
                        ) {
                            configManager.config.accentColor = choice
                            configManager.save()
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Waveform Style
            Section {
                Picker("Style", selection: $configManager.config.waveformStyle) {
                    ForEach(WaveformStyle.allCases, id: \.self) { style in
                        VStack(alignment: .leading) {
                            Text(style.displayName)
                            Text(style.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: configManager.config.waveformStyle) { _, _ in
                    configManager.save()
                }

                // Live preview
                WaveformPreview(
                    style: configManager.config.waveformStyle,
                    phase: previewPhase,
                    opacity: configManager.config.panelOpacity
                )
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.top, 4)
            } header: {
                Text("Waveform Style")
            }

            // Panel Opacity
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Panel Opacity")
                        Spacer()
                        Text("\(Int(configManager.config.panelOpacity * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $configManager.config.panelOpacity, in: 0.5...1.0, step: 0.05)
                        .onChange(of: configManager.config.panelOpacity) { _, _ in
                            configManager.save()
                        }
                }
            } header: {
                Text("Transparency")
            } footer: {
                Text("Controls the background opacity of the voice panel.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Animation Speed
            Section {
                Toggle("Reduce Animations", isOn: $configManager.config.reduceAnimations)
                    .onChange(of: configManager.config.reduceAnimations) { _, _ in
                        configManager.save()
                    }
            } header: {
                Text("Motion")
            } footer: {
                Text("Reduces waveform and UI animations. This also activates when the system \"Reduce Motion\" accessibility setting is enabled.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { startPreview() }
        .onDisappear { stopPreview() }
    }

    private func startPreview() {
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in
                previewPhase += 0.08
            }
        }
    }

    private func stopPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
    }
}

// MARK: - Accent Color Button

/// A circular color swatch button for the accent color picker.
struct AccentColorButton: View {
    let choice: AccentColorChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(choice.color ?? Color.accentColor)
                        .frame(width: 32, height: 32)

                    if choice == .system {
                        // Show a gradient for "System"
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [.blue, .purple, .pink, .orange, .blue],
                                    center: .center
                                )
                            )
                            .frame(width: 32, height: 32)
                    }

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }

                Text(choice.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Waveform Preview

/// A small preview of the waveform style for the appearance settings.
struct WaveformPreview: View {
    let style: WaveformStyle
    let phase: Double
    let opacity: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .opacity(opacity)

            Canvas { context, size in
                let midY = size.height / 2
                let width = size.width

                switch style {
                case .subtle:
                    drawSubtleWave(context: context, midY: midY, width: width, size: size)
                case .expressive:
                    drawExpressiveBars(context: context, midY: midY, width: width, size: size)
                case .minimal:
                    drawMinimalDots(context: context, midY: midY, width: width, size: size)
                }
            }
        }
    }

    private func drawSubtleWave(context: GraphicsContext, midY: CGFloat, width: CGFloat, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))

        for x in stride(from: 0.0, through: width, by: 2.0) {
            let normalizedX = x / width
            let wave = sin(normalizedX * .pi * 4.0 + phase * 2.0)
            let envelope = sin(normalizedX * .pi)
            let y = midY + wave * midY * 0.4 * envelope
            path.addLine(to: CGPoint(x: x, y: y))
        }

        context.stroke(path, with: .color(.blue.opacity(0.7)), lineWidth: 2)
    }

    private func drawExpressiveBars(context: GraphicsContext, midY: CGFloat, width: CGFloat, size: CGSize) {
        let barCount = 20
        let barWidth = width / CGFloat(barCount) * 0.6
        let gap = width / CGFloat(barCount)

        for i in 0..<barCount {
            let x = CGFloat(i) * gap + gap * 0.2
            let normalizedPos = CGFloat(i) / CGFloat(barCount)
            let height = abs(sin(normalizedPos * .pi * 2.0 + phase * 3.0)) * midY * 0.8 + 4

            let rect = CGRect(
                x: x,
                y: midY - height / 2,
                width: barWidth,
                height: height
            )

            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(.purple.opacity(0.6))
            )
        }
    }

    private func drawMinimalDots(context: GraphicsContext, midY: CGFloat, width: CGFloat, size: CGSize) {
        let dotCount = 5
        let spacing = width / CGFloat(dotCount + 1)

        for i in 0..<dotCount {
            let x = spacing * CGFloat(i + 1)
            let scale = 1.0 + sin(phase * 2.0 + Double(i) * 0.8) * 0.4
            let dotSize = 8.0 * scale

            let rect = CGRect(
                x: x - dotSize / 2,
                y: midY - dotSize / 2,
                width: dotSize,
                height: dotSize
            )

            context.fill(
                Path(ellipseIn: rect),
                with: .color(.blue.opacity(0.5 + scale * 0.2))
            )
        }
    }
}
