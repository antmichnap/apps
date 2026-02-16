import SwiftUI

/// Main app view combining all music-making components
struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var sequencer = PatternSequencer()

    @State private var selectedTab: Tab = .play

    enum Tab: String, CaseIterable {
        case play = "Play"
        case sequence = "Sequence"
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(white: 0.28), Color(white: 0.15), Color(white: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                tabSelector
                    .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 20) {
                        if selectedTab == .play {
                            playView
                        } else {
                            sequenceView
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 80)
                }

                // Keyboard always visible at bottom
                VStack(spacing: 8) {
                    Divider()
                        .background(Color.white.opacity(0.08))

                    ScrollView(.horizontal, showsIndicators: false) {
                        KeyboardView(
                            onNoteOn: { note in
                                audioEngine.noteOn(note)
                                if sequencer.isRecording {
                                    sequencer.recordNote(note)
                                }
                            },
                            onNoteOff: { audioEngine.noteOff($0) }
                        )
                    }
                    .padding(.bottom, 8)
                }
                .background(Color.black.opacity(0.3))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            connectSequencer()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pulse")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("music maker")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(white: 0.55))
            }

            Spacer()

            // Waveform selector
            Menu {
                ForEach(AudioEngine.Waveform.allCases) { waveform in
                    Button {
                        audioEngine.waveform = waveform
                    } label: {
                        HStack {
                            Text(waveform.rawValue)
                            if audioEngine.waveform == waveform {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: waveformIcon)
                    Text(audioEngine.waveform.rawValue)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(white: 0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
            }
        }
    }

    private var waveformIcon: String {
        switch audioEngine.waveform {
        case .sine:      return "waveform"
        case .triangle:  return "triangle"
        case .saw:       return "chart.xyaxis.line"
        case .square:    return "square.fill"
        case .wavetable: return "waveform.circle"
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedTab == tab
                                ? Color(white: 0.3)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }

    // MARK: - Play View

    private var playView: some View {
        VStack(spacing: 16) {
            // Drum pads
            sectionHeader("Drum Pads", icon: "square.grid.2x2.fill")
            DrumPadView { drum in
                audioEngine.playDrum(drum)
            }

            // Synth + Filter combined
            sectionHeader("Synth & Filter", icon: "slider.horizontal.3")
            VStack(spacing: 10) {
                controlSlider(label: "Volume", value: $audioEngine.volume, range: 0...1)
                controlSlider(label: "Attack", value: $audioEngine.attack, range: 0.001...0.5)
                controlSlider(label: "Release", value: $audioEngine.release, range: 0.05...2.0)
                Divider().background(Color.white.opacity(0.08))
                controlSlider(label: "Cutoff", value: $audioEngine.filterCutoff, range: 0...0.99)
                controlSlider(label: "Reso", value: $audioEngine.filterResonance, range: 0...1)
            }
            .padding(14)
            .background(controlCard)

            // Reverb + Delay combined
            sectionHeader("Effects", icon: "dot.radiowaves.right")
            VStack(spacing: 10) {
                controlSlider(label: "Reverb", value: $audioEngine.reverbMix, range: 0...1)
                controlSlider(label: "Decay", value: $audioEngine.reverbDecay, range: 0...1)
                Divider().background(Color.white.opacity(0.08))
                controlSlider(label: "Delay", value: $audioEngine.delayMix, range: 0...1)
                controlSlider(label: "Time", value: $audioEngine.delayTime, range: 0.05...1.0)
                controlSlider(label: "Feedbk", value: $audioEngine.delayFeedback, range: 0...0.9)
            }
            .padding(14)
            .background(controlCard)
        }
    }

    // MARK: - Sequence View

    private var sequenceView: some View {
        VStack(spacing: 16) {
            sectionHeader("Step Sequencer", icon: "waveform.badge.plus")
            SequencerView(sequencer: sequencer)
        }
    }

    // MARK: - Shared UI

    private var controlCard: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    private func controlSlider(label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 56, alignment: .leading)

            Slider(value: value, in: range)
                .tint(Color(white: 0.5))

            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 36)
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.55))
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
        }
    }

    // MARK: - Sequencer Connection

    private func connectSequencer() {
        sequencer.onDrumTrigger = { drum in
            audioEngine.playDrum(drum)
        }
        sequencer.onNoteTrigger = { note in
            audioEngine.noteOn(note)
        }
        sequencer.onNoteRelease = { note in
            audioEngine.noteOff(note)
        }
    }
}

#Preview {
    ContentView()
}
