import Foundation
import Combine

/// Step sequencer for generating drum and note patterns
final class PatternSequencer: ObservableObject {

    // MARK: - Types

    enum TrackType: String, CaseIterable, Identifiable {
        case kick = "Kick"
        case snare = "Snare"
        case hihat = "Hi-Hat"
        case openHat = "Open Hat"
        case clap = "Clap"
        case tomHi = "Tom Hi"
        case tomLo = "Tom Lo"
        case shaker = "Shaker"
        case synth = "Synth"

        var id: String { rawValue }

        var drumSound: AudioEngine.DrumSound? {
            switch self {
            case .kick:    return .kick
            case .snare:   return .snare
            case .hihat:   return .hihat
            case .openHat: return .openHat
            case .clap:    return .clap
            case .tomHi:   return .tomHi
            case .tomLo:   return .tomLo
            case .shaker:  return .shaker
            case .synth:   return nil
            }
        }
    }

    struct Step: Identifiable {
        let id = UUID()
        var drums: Set<String> = []  // DrumSound rawValues that are active
        var note: Int? = nil         // MIDI note, nil = silent
    }

    // MARK: - Published State

    @Published var steps: [Step] = Array(repeating: Step(), count: 16)
    @Published var currentStep: Int = -1
    @Published var isPlaying: Bool = false
    @Published var isRecording: Bool = false
    @Published var bpm: Double = 120

    // MARK: - Callbacks

    var onDrumTrigger: ((AudioEngine.DrumSound) -> Void)?
    var onNoteTrigger: ((Int) -> Void)?
    var onNoteRelease: ((Int) -> Void)?

    // MARK: - Private

    private var timer: Timer?
    private var lastNote: Int?

    // MARK: - Preset Patterns

    enum Preset: String, CaseIterable, Identifiable {
        case empty = "Empty"
        case fourOnFloor = "Four on Floor"
        case breakbeat = "Breakbeat"
        case hiphop = "Hip Hop"

        var id: String { rawValue }
    }

    func loadPreset(_ preset: Preset) {
        steps = Array(repeating: Step(), count: 16)

        switch preset {
        case .empty:
            break

        case .fourOnFloor:
            for i in stride(from: 0, to: 16, by: 4) {
                steps[i].drums.insert(AudioEngine.DrumSound.kick.rawValue)
            }
            for i in stride(from: 4, to: 16, by: 8) {
                steps[i].drums.insert(AudioEngine.DrumSound.snare.rawValue)
            }
            for i in stride(from: 0, to: 16, by: 2) {
                steps[i].drums.insert(AudioEngine.DrumSound.hihat.rawValue)
            }
            let notes = [60, 60, 64, 64, 67, 67, 72, 72, 71, 71, 67, 67, 64, 64, 60, 60]
            for (i, note) in notes.enumerated() {
                steps[i].note = note
            }

        case .breakbeat:
            steps[0].drums.insert(AudioEngine.DrumSound.kick.rawValue)
            steps[3].drums.insert(AudioEngine.DrumSound.kick.rawValue)
            steps[6].drums.insert(AudioEngine.DrumSound.kick.rawValue)
            steps[10].drums.insert(AudioEngine.DrumSound.kick.rawValue)
            steps[4].drums.insert(AudioEngine.DrumSound.snare.rawValue)
            steps[12].drums.insert(AudioEngine.DrumSound.snare.rawValue)
            for i in stride(from: 0, to: 16, by: 2) {
                steps[i].drums.insert(AudioEngine.DrumSound.hihat.rawValue)
            }
            steps[7].drums.insert(AudioEngine.DrumSound.openHat.rawValue)
            steps[15].drums.insert(AudioEngine.DrumSound.openHat.rawValue)
            steps[2].drums.insert(AudioEngine.DrumSound.tomHi.rawValue)
            steps[14].drums.insert(AudioEngine.DrumSound.tomLo.rawValue)
            let notes: [Int?] = [60, nil, 63, nil, 60, nil, 67, nil, 65, nil, 63, nil, 60, nil, 58, nil]
            for (i, note) in notes.enumerated() {
                steps[i].note = note
            }

        case .hiphop:
            steps[0].drums.insert(AudioEngine.DrumSound.kick.rawValue)
            steps[7].drums.insert(AudioEngine.DrumSound.kick.rawValue)
            steps[9].drums.insert(AudioEngine.DrumSound.kick.rawValue)
            steps[4].drums.insert(AudioEngine.DrumSound.snare.rawValue)
            steps[12].drums.insert(AudioEngine.DrumSound.snare.rawValue)
            steps[2].drums.insert(AudioEngine.DrumSound.clap.rawValue)
            steps[14].drums.insert(AudioEngine.DrumSound.clap.rawValue)
            for i in 0..<16 {
                steps[i].drums.insert(AudioEngine.DrumSound.hihat.rawValue)
            }
            for i in stride(from: 1, to: 16, by: 4) {
                steps[i].drums.insert(AudioEngine.DrumSound.shaker.rawValue)
            }
            let notes: [Int?] = [55, nil, nil, 58, nil, 60, nil, nil, 63, nil, nil, 60, nil, 58, nil, nil]
            for (i, note) in notes.enumerated() {
                steps[i].note = note
            }
        }
    }

    // MARK: - Transport

    func togglePlayback() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }

    func play() {
        isPlaying = true
        currentStep = -1
        scheduleNextStep()
    }

    func stop() {
        isPlaying = false
        isRecording = false
        timer?.invalidate()
        timer = nil
        if let last = lastNote {
            onNoteRelease?(last)
            lastNote = nil
        }
        currentStep = -1
    }

    func toggleRecording() {
        if isRecording {
            isRecording = false
        } else {
            isRecording = true
            if !isPlaying {
                play()
            }
        }
    }

    func recordNote(_ midiNote: Int) {
        guard isRecording && isPlaying && currentStep >= 0 && currentStep < steps.count else { return }
        steps[currentStep].note = midiNote
    }

    private func scheduleNextStep() {
        let interval = 60.0 / bpm / 4.0  // 16th notes

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            self.advanceStep()
            self.scheduleNextStep()
        }
    }

    private func advanceStep() {
        currentStep = (currentStep + 1) % steps.count
        let step = steps[currentStep]

        // Release previous note
        if let last = lastNote {
            onNoteRelease?(last)
            lastNote = nil
        }

        // Trigger drums
        for drumSound in AudioEngine.DrumSound.allCases {
            if step.drums.contains(drumSound.rawValue) {
                onDrumTrigger?(drumSound)
            }
        }

        // Trigger note
        if let note = step.note {
            onNoteTrigger?(note)
            lastNote = note
        }
    }

    // MARK: - Step Editing

    func toggleTrack(_ track: TrackType, at index: Int) {
        guard index >= 0 && index < steps.count else { return }

        if track == .synth {
            // Toggle synth note on/off (default to C4 = 60 when toggling on)
            if steps[index].note != nil {
                steps[index].note = nil
            } else {
                steps[index].note = 60
            }
        } else if let drum = track.drumSound {
            if steps[index].drums.contains(drum.rawValue) {
                steps[index].drums.remove(drum.rawValue)
            } else {
                steps[index].drums.insert(drum.rawValue)
            }
        }
    }

    func setNote(at index: Int, note: Int?) {
        guard index >= 0 && index < steps.count else { return }
        steps[index].note = note
    }

    func stepIsActive(track: TrackType, at index: Int) -> Bool {
        let step = steps[index]
        if track == .synth {
            return step.note != nil
        }
        guard let drum = track.drumSound else { return false }
        return step.drums.contains(drum.rawValue)
    }

    func randomizePattern() {
        let notes = [48, 50, 52, 53, 55, 57, 59, 60, 62, 64, 65, 67]

        for i in 0..<steps.count {
            steps[i].drums.removeAll()

            if Bool.random() && (i % 4 == 0 || Bool.random()) {
                steps[i].drums.insert(AudioEngine.DrumSound.kick.rawValue)
            }
            if Bool.random() && (i % 8 == 4 || i % 8 == 12) {
                steps[i].drums.insert(AudioEngine.DrumSound.snare.rawValue)
            }
            if Bool.random() {
                steps[i].drums.insert(AudioEngine.DrumSound.hihat.rawValue)
            }
            if Double.random(in: 0...1) < 0.1 {
                steps[i].drums.insert(AudioEngine.DrumSound.openHat.rawValue)
            }
            if Double.random(in: 0...1) < 0.15 {
                steps[i].drums.insert(AudioEngine.DrumSound.clap.rawValue)
            }
            if Double.random(in: 0...1) < 0.1 {
                steps[i].drums.insert(AudioEngine.DrumSound.tomHi.rawValue)
            }
            if Double.random(in: 0...1) < 0.08 {
                steps[i].drums.insert(AudioEngine.DrumSound.tomLo.rawValue)
            }
            if Double.random(in: 0...1) < 0.2 {
                steps[i].drums.insert(AudioEngine.DrumSound.shaker.rawValue)
            }
            steps[i].note = Bool.random() ? notes.randomElement() : nil
        }
    }
}
