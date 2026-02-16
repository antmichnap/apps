import SwiftUI

/// Two-octave playable keyboard
struct KeyboardView: View {
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    // Two octaves starting at C3 (MIDI 48)
    private let startNote = 48
    private let whiteNoteOffsets = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23]
    private let blackNoteInfo: [(offset: Int, position: Int)] = [
        (1, 0), (3, 1), (6, 3), (8, 4), (10, 5),
        (13, 7), (15, 8), (18, 10), (20, 11), (22, 12)
    ]

    private let whiteKeyWidth: CGFloat = 38
    private let blackKeyWidth: CGFloat = 24
    private let whiteKeyHeight: CGFloat = 110
    private let blackKeyHeight: CGFloat = 65

    @State private var pressedNotes: Set<Int> = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            // White keys
            HStack(spacing: 1.5) {
                ForEach(whiteNoteOffsets, id: \.self) { offset in
                    let midiNote = startNote + offset
                    WhiteKey(
                        note: noteLabel(midiNote),
                        isPressed: pressedNotes.contains(midiNote)
                    )
                    .frame(width: whiteKeyWidth, height: whiteKeyHeight)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !pressedNotes.contains(midiNote) {
                                    pressedNotes.insert(midiNote)
                                    onNoteOn(midiNote)
                                }
                            }
                            .onEnded { _ in
                                pressedNotes.remove(midiNote)
                                onNoteOff(midiNote)
                            }
                    )
                }
            }

            // Black keys
            ForEach(blackNoteInfo, id: \.offset) { info in
                let midiNote = startNote + info.offset
                BlackKey(isPressed: pressedNotes.contains(midiNote))
                    .frame(width: blackKeyWidth, height: blackKeyHeight)
                    .offset(
                        x: CGFloat(info.position) * (whiteKeyWidth + 1.5) + whiteKeyWidth - blackKeyWidth / 2 + 0.75,
                        y: 0
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !pressedNotes.contains(midiNote) {
                                    pressedNotes.insert(midiNote)
                                    onNoteOn(midiNote)
                                }
                            }
                            .onEnded { _ in
                                pressedNotes.remove(midiNote)
                                onNoteOff(midiNote)
                            }
                    )
                    .zIndex(1)
            }
        }
        .padding(.horizontal, 4)
    }

    private func noteLabel(_ midiNote: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let name = names[midiNote % 12]
        let octave = (midiNote / 12) - 1
        if name.contains("#") { return "" }
        return "\(name)\(octave)"
    }
}

// MARK: - Key Views

private struct WhiteKey: View {
    let note: String
    let isPressed: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    isPressed
                        ? LinearGradient(colors: [Color(white: 0.75), Color(white: 0.65)],
                                         startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color(white: 0.92), Color(white: 0.85)],
                                         startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)

            Text(note)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(isPressed ? Color(white: 0.3) : Color(white: 0.5))
                .padding(.bottom, 6)
        }
    }
}

private struct BlackKey: View {
    let isPressed: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                isPressed
                    ? LinearGradient(colors: [Color(white: 0.35), Color(white: 0.28)],
                                     startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)],
                                     startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
    }
}
