import SwiftUI

/// Visual step sequencer grid with transport controls
struct SequencerView: View {
    @ObservedObject var sequencer: PatternSequencer
    @State private var selectedRow: AudioEngine.DrumSound = .kick

    private let drumRows: [AudioEngine.DrumSound] = [.kick, .snare, .hihat, .clap]

    var body: some View {
        VStack(spacing: 12) {
            // Transport bar
            transportBar

            // Drum row selector
            drumSelector

            // Step grid
            stepGrid

            // BPM control
            bpmControl
        }
    }

    // MARK: - Transport

    private var transportBar: some View {
        HStack(spacing: 16) {
            Button {
                sequencer.togglePlayback()
            } label: {
                Image(systemName: sequencer.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(sequencer.isPlaying ? Color(hex: "FF6B6B") : Color(hex: "4ECDC4"))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            // Preset menu
            Menu {
                ForEach(PatternSequencer.Preset.allCases) { preset in
                    Button(preset.rawValue) {
                        sequencer.loadPreset(preset)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                    Text("Presets")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.15))
                )
            }

            Button {
                sequencer.randomizePattern()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "dice.fill")
                    Text("Random")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Drum Selector

    private var drumSelector: some View {
        HStack(spacing: 6) {
            ForEach(drumRows) { drum in
                Button {
                    selectedRow = drum
                } label: {
                    Text(drum.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(selectedRow == drum ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedRow == drum ? drumColor(drum) : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Step Grid

    private var stepGrid: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { index in
                let isActive = stepIsActive(at: index)
                let isCurrent = sequencer.currentStep == index

                RoundedRectangle(cornerRadius: 4)
                    .fill(stepColor(active: isActive, current: isCurrent, index: index))
                    .frame(height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isCurrent ? Color.white.opacity(0.8) : Color.clear, lineWidth: 1.5)
                    )
                    .onTapGesture {
                        sequencer.toggleDrum(selectedRow, at: index)
                    }
            }
        }
    }

    // MARK: - BPM

    private var bpmControl: some View {
        HStack(spacing: 8) {
            Text("BPM")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))

            Slider(value: $sequencer.bpm, in: 60...200, step: 1)
                .tint(Color(hex: "9B4DCA"))

            Text("\(Int(sequencer.bpm))")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 36)
        }
    }

    // MARK: - Helpers

    private func stepIsActive(at index: Int) -> Bool {
        let step = sequencer.steps[index]
        switch selectedRow {
        case .kick:  return step.kick
        case .snare: return step.snare
        case .hihat: return step.hihat
        case .clap:  return step.clap
        }
    }

    private func stepColor(active: Bool, current: Bool, index: Int) -> Color {
        if active && current {
            return drumColor(selectedRow)
        } else if active {
            return drumColor(selectedRow).opacity(0.65)
        } else if current {
            return Color.white.opacity(0.2)
        } else {
            // Subtle grouping every 4 steps
            return index % 4 < 2
                ? Color.white.opacity(0.08)
                : Color.white.opacity(0.05)
        }
    }

    private func drumColor(_ drum: AudioEngine.DrumSound) -> Color {
        switch drum {
        case .kick:  return Color(hex: "FF6B6B")
        case .snare: return Color(hex: "4ECDC4")
        case .hihat: return Color(hex: "FFE66D")
        case .clap:  return Color(hex: "A8E6CF")
        }
    }
}
