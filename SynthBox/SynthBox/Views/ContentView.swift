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
                colors: [Color(hex: "1A1A2E"), Color(hex: "16213E"), Color(hex: "0F3460")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Tab selector
                tabSelector
                    .padding(.top, 12)

                // Content
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
                    .padding(.bottom, 24)
                }

                // Keyboard always visible at bottom
                VStack(spacing: 8) {
                    Divider()
                        .background(Color.white.opacity(0.1))

                    ScrollView(.horizontal, showsIndicators: false) {
                        KeyboardView(
                            onNoteOn: { audioEngine.noteOn($0) },
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
                Text("SynthBox")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("music maker")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "9B4DCA"))
            }

            Spacer()

            // Waveform toggle
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
                    Image(systemName: audioEngine.waveform == .sine ? "waveform" : "chart.xyaxis.line")
                    Text(audioEngine.waveform.rawValue)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: "9B4DCA").opacity(0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(hex: "9B4DCA").opacity(0.6), lineWidth: 1)
                        )
                )
            }
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
                        .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedTab == tab
                                ? Color(hex: "9B4DCA").opacity(0.3)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }

    // MARK: - Play View

    private var playView: some View {
        VStack(spacing: 20) {
            // Drum pads
            sectionHeader("Drum Pads", icon: "square.grid.2x2.fill")
            DrumPadView { drum in
                audioEngine.playDrum(drum)
            }

            // Synth controls
            sectionHeader("Synth Controls", icon: "slider.horizontal.3")
            synthControls
        }
    }

    // MARK: - Sequence View

    private var sequenceView: some View {
        VStack(spacing: 16) {
            sectionHeader("Step Sequencer", icon: "waveform.badge.plus")
            SequencerView(sequencer: sequencer)
        }
    }

    // MARK: - Synth Controls

    private var synthControls: some View {
        VStack(spacing: 14) {
            controlSlider(label: "Volume", value: $audioEngine.volume, range: 0...1)
            controlSlider(label: "Attack", value: $audioEngine.attack, range: 0.001...0.5)
            controlSlider(label: "Release", value: $audioEngine.release, range: 0.05...2.0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func controlSlider(label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 56, alignment: .leading)

            Slider(value: value, in: range)
                .tint(Color(hex: "9B4DCA"))

            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 36)
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "9B4DCA"))
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
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
