import SwiftUI

/// Grid of drum pads for triggering drum sounds
struct DrumPadView: View {
    let onDrumTap: (AudioEngine.DrumSound) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(AudioEngine.DrumSound.allCases) { drum in
                DrumPadButton(drum: drum, onTap: onDrumTap)
            }
        }
    }
}

private struct DrumPadButton: View {
    let drum: AudioEngine.DrumSound
    let onTap: (AudioEngine.DrumSound) -> Void

    @State private var isPressed = false

    private let padDefault = Color(white: 0.28)
    private let padPressed = Color(white: 0.10)

    private var padIcon: String {
        switch drum {
        case .kick:    return "speaker.wave.3.fill"
        case .snare:   return "waveform"
        case .hihat:   return "circle.dotted"
        case .openHat: return "circle.circle"
        case .clap:    return "hands.clap.fill"
        case .tomHi:   return "circle.fill"
        case .tomLo:   return "circle.bottomhalf.filled"
        case .shaker:  return "wind"
        }
    }

    var body: some View {
        Button {
            isPressed = true
            onTap(drum)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: padIcon)
                    .font(.system(size: 16, weight: .semibold))
                Text(drum.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPressed ? padPressed : padDefault)
                    .shadow(color: .black.opacity(0.4), radius: isPressed ? 1 : 4, y: isPressed ? 0 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isPressed ? 0.3 : 0.08), lineWidth: 1)
            )
            .foregroundColor(.white.opacity(0.85))
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
    }
}
