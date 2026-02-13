import Foundation
import Combine

/// Step sequencer for generating drum and note patterns
final class PatternSequencer: ObservableObject {

    // MARK: - Types

    struct Step: Identifiable {
        let id = UUID()
        var kick: Bool = false
        var snare: Bool = false
        var hihat: Bool = false
        var clap: Bool = false
        var note: Int? = nil  // MIDI note, nil = silent
    }

    // MARK: - Published State

    @Published var steps: [Step] = Array(repeating: Step(), count: 16)
    @Published var currentStep: Int = -1
    @Published var isPlaying: Bool = false
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
                steps[i].kick = true
            }
            for i in stride(from: 4, to: 16, by: 8) {
                steps[i].snare = true
            }
            for i in stride(from: 0, to: 16, by: 2) {
                steps[i].hihat = true
            }
            // Melody: simple ascending pattern
            let notes = [60, 60, 64, 64, 67, 67, 72, 72, 71, 71, 67, 67, 64, 64, 60, 60]
            for (i, note) in notes.enumerated() {
                steps[i].note = note
            }

        case .breakbeat:
            steps[0].kick = true
            steps[3].kick = true
            steps[6].kick = true
            steps[10].kick = true
            steps[4].snare = true
            steps[12].snare = true
            for i in stride(from: 0, to: 16, by: 2) {
                steps[i].hihat = true
            }
            steps[7].hihat = true
            steps[15].hihat = true
            // Syncopated melody
            let notes: [Int?] = [60, nil, 63, nil, 60, nil, 67, nil, 65, nil, 63, nil, 60, nil, 58, nil]
            for (i, note) in notes.enumerated() {
                steps[i].note = note
            }

        case .hiphop:
            steps[0].kick = true
            steps[7].kick = true
            steps[9].kick = true
            steps[4].snare = true
            steps[12].snare = true
            steps[2].clap = true
            steps[14].clap = true
            for i in 0..<16 {
                steps[i].hihat = true
            }
            // Chill melody
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
        timer?.invalidate()
        timer = nil
        if let last = lastNote {
            onNoteRelease?(last)
            lastNote = nil
        }
        currentStep = -1
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
        if step.kick  { onDrumTrigger?(.kick) }
        if step.snare { onDrumTrigger?(.snare) }
        if step.hihat { onDrumTrigger?(.hihat) }
        if step.clap  { onDrumTrigger?(.clap) }

        // Trigger note
        if let note = step.note {
            onNoteTrigger?(note)
            lastNote = note
        }
    }

    // MARK: - Step Editing

    func toggleDrum(_ drum: AudioEngine.DrumSound, at index: Int) {
        guard index >= 0 && index < steps.count else { return }
        switch drum {
        case .kick:  steps[index].kick.toggle()
        case .snare: steps[index].snare.toggle()
        case .hihat: steps[index].hihat.toggle()
        case .clap:  steps[index].clap.toggle()
        }
    }

    func randomizePattern() {
        let notes = [48, 50, 52, 53, 55, 57, 59, 60, 62, 64, 65, 67]

        for i in 0..<steps.count {
            steps[i].kick = Bool.random() && (i % 4 == 0 || Bool.random())
            steps[i].snare = Bool.random() && (i % 8 == 4 || i % 8 == 12)
            steps[i].hihat = Bool.random()
            steps[i].clap = Double.random(in: 0...1) < 0.15
            steps[i].note = Bool.random() ? notes.randomElement() : nil
        }
    }
}
