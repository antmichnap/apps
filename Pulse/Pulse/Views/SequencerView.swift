import SwiftUI

/// Visual step sequencer grid with transport controls and note input
struct SequencerView: View {
    @ObservedObject var sequencer: PatternSequencer
    @State private var selectedTrack: PatternSequencer.TrackType = .kick
    @State private var editingNoteIndex: Int? = nil

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        VStack(spacing: 12) {
            transportBar
            trackSelector
            stepGrid

            if selectedTrack == .synth {
                noteEditor
            }

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
                            .fill(sequencer.isPlaying ? Color(white: 0.45) : Color(white: 0.3))
                    )
            }
            .buttonStyle(.plain)

            Button {
                sequencer.toggleRecording()
            } label: {
                Image(systemName: "record.circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(sequencer.isRecording ? .red : .white)
                    .frame(width: 44, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(sequencer.isRecording ? Color.red.opacity(0.25) : Color(white: 0.3))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

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
                        .fill(Color.white.opacity(0.12))
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
                        .fill(Color.white.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Track Selector

    private var trackSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(PatternSequencer.TrackType.allCases) { track in
                    Button {
                        selectedTrack = track
                        editingNoteIndex = nil
                    } label: {
                        Text(track.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(selectedTrack == track ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTrack == track
                                          ? trackColor(track)
                                          : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Step Grid

    private var stepGrid: some View {
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { index in
                let isActive = sequencer.stepIsActive(track: selectedTrack, at: index)
                let isCurrent = sequencer.currentStep == index

                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(stepColor(active: isActive, current: isCurrent, index: index))
                        .frame(height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isCurrent ? Color.white.opacity(0.7) : Color.clear, lineWidth: 1.5)
                        )
                        .overlay(
                            // Show note name on synth track
                            Group {
                                if selectedTrack == .synth, let note = sequencer.steps[index].note {
                                    Text(midiNoteName(note))
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                            }
                        )
                        .onTapGesture {
                            if selectedTrack == .synth && isActive {
                                // Tap active synth step to edit the note
                                editingNoteIndex = (editingNoteIndex == index) ? nil : index
                            } else {
                                sequencer.toggleTrack(selectedTrack, at: index)
                            }
                        }

                    // Highlight indicator for edited step
                    if editingNoteIndex == index {
                        Rectangle()
                            .fill(Color.white.opacity(0.6))
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                }
            }
        }
    }

    // MARK: - Note Editor

    private var noteEditor: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pianokeys")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                Text(editingNoteIndex != nil ? "Set note for step \(editingNoteIndex! + 1)" : "Tap an active synth step to edit its note")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }

            if editingNoteIndex != nil {
                // Octave and note picker
                VStack(spacing: 6) {
                    // Note buttons
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                        ForEach(0..<12, id: \.self) { noteIdx in
                            let currentNote = sequencer.steps[editingNoteIndex!].note ?? 60
                            let octave = currentNote / 12
                            let candidateNote = octave * 12 + noteIdx
                            let isSelected = (currentNote % 12) == noteIdx

                            Button {
                                sequencer.setNote(at: editingNoteIndex!, note: candidateNote)
                            } label: {
                                Text(noteNames[noteIdx])
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(isSelected ? Color(white: 0.4) : Color(white: 0.15))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Octave selector
                    HStack(spacing: 6) {
                        Text("Oct")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                        ForEach(2..<7, id: \.self) { oct in
                            let currentNote = sequencer.steps[editingNoteIndex!].note ?? 60
                            let currentOctave = currentNote / 12
                            let isSelected = currentOctave == oct

                            Button {
                                let notePart = currentNote % 12
                                sequencer.setNote(at: editingNoteIndex!, note: oct * 12 + notePart)
                            } label: {
                                Text("\(oct - 1)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                                    .frame(width: 32, height: 26)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(isSelected ? Color(white: 0.4) : Color(white: 0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        // Delete note button
                        Button {
                            sequencer.setNote(at: editingNoteIndex!, note: nil)
                            editingNoteIndex = nil
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 32, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(white: 0.2))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.1))
                )
            }
        }
    }

    // MARK: - BPM

    private var bpmControl: some View {
        HStack(spacing: 8) {
            Text("BPM")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))

            Slider(value: $sequencer.bpm, in: 60...200, step: 1)
                .tint(Color(white: 0.5))

            Text("\(Int(sequencer.bpm))")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 36)
        }
    }

    // MARK: - Helpers

    private func midiNoteName(_ note: Int) -> String {
        let name = noteNames[note % 12]
        let octave = (note / 12) - 1
        return "\(name)\(octave)"
    }

    private func trackColor(_ track: PatternSequencer.TrackType) -> Color {
        switch track {
        case .kick:    return Color(white: 0.35)
        case .snare:   return Color(white: 0.38)
        case .hihat:   return Color(white: 0.32)
        case .openHat: return Color(white: 0.36)
        case .clap:    return Color(white: 0.34)
        case .tomHi:   return Color(white: 0.33)
        case .tomLo:   return Color(white: 0.30)
        case .shaker:  return Color(white: 0.37)
        case .synth:   return Color(white: 0.42)
        }
    }

    private func stepColor(active: Bool, current: Bool, index: Int) -> Color {
        if active && current {
            return Color(white: 0.55)
        } else if active {
            return Color(white: 0.40)
        } else if current {
            return Color.white.opacity(0.15)
        } else {
            return index % 4 < 2
                ? Color.white.opacity(0.06)
                : Color.white.opacity(0.04)
        }
    }
}
