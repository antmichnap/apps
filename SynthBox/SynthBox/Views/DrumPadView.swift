import SwiftUI

/// Grid of drum pads for triggering drum sounds
struct DrumPadView: View {
    let onDrumTap: (AudioEngine.DrumSound) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
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

    private var padColor: Color {
        switch drum {
        case .kick:  return Color(hex: "FF6B6B")
        case .snare: return Color(hex: "4ECDC4")
        case .hihat: return Color(hex: "FFE66D")
        case .clap:  return Color(hex: "A8E6CF")
        }
    }

    private var padIcon: String {
        switch drum {
        case .kick:  return "speaker.wave.3.fill"
        case .snare: return "waveform"
        case .hihat: return "circle.dotted"
        case .clap:  return "hands.clap.fill"
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
            VStack(spacing: 6) {
                Image(systemName: padIcon)
                    .font(.system(size: 20, weight: .semibold))
                Text(drum.rawValue)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(padColor.opacity(isPressed ? 1.0 : 0.75))
                    .shadow(color: padColor.opacity(0.4), radius: isPressed ? 2 : 6, y: isPressed ? 1 : 3)
            )
            .foregroundColor(.white)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(.plain)
    }
}
