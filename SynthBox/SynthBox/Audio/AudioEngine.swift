import AVFoundation
import Foundation

/// Core audio engine handling synthesis and drum playback
final class AudioEngine: ObservableObject {

    // MARK: - Types

    enum Waveform: String, CaseIterable, Identifiable {
        case sine = "Sine"
        case saw = "Saw"

        var id: String { rawValue }
    }

    enum DrumSound: String, CaseIterable, Identifiable {
        case kick = "Kick"
        case snare = "Snare"
        case hihat = "Hi-Hat"
        case clap = "Clap"

        var id: String { rawValue }
    }

    // MARK: - Published State

    @Published var waveform: Waveform = .saw
    @Published var volume: Float = 0.6
    @Published var attack: Float = 0.01
    @Published var release: Float = 0.3

    // MARK: - Audio Properties

    private let engine = AVAudioEngine()
    private let synthNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
        return noErr // Replaced at init
    }

    private var sampleRate: Double = 44100.0
    private var activeNotes: [Int: NoteState] = [:]
    private let noteLock = NSLock()

    private struct NoteState {
        var phase: Double = 0.0
        var envelope: Double = 0.0
        var releasing: Bool = false
        var releaseStart: Double = 0.0
    }

    // MARK: - Drum Properties

    private var drumPhases: [DrumSound: DrumState] = [:]

    private struct DrumState {
        var phase: Double = 0.0
        var time: Double = 0.0
        var active: Bool = false
    }

    // MARK: - Init

    init() {
        setupAudioSession()
        setupEngine()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(44100)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func setupEngine() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        sampleRate = format.sampleRate

        let sr = sampleRate

        let sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }

            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            for frame in 0..<frames {
                var sample: Float = 0.0

                // Synth voices
                self.noteLock.lock()
                var finishedNotes: [Int] = []

                for (note, var state) in self.activeNotes {
                    let frequency = self.midiNoteToFrequency(note)
                    let phaseIncrement = frequency / sr

                    // Generate waveform
                    var wave: Double
                    switch self.waveform {
                    case .sine:
                        wave = sin(state.phase * 2.0 * .pi)
                    case .saw:
                        wave = 2.0 * (state.phase - floor(state.phase + 0.5))
                    }

                    // Envelope
                    if state.releasing {
                        let releaseTime = Double(self.release)
                        state.releaseStart += 1.0 / sr
                        let releaseProgress = state.releaseStart / releaseTime
                        state.envelope = max(0, 1.0 - releaseProgress)
                        if state.envelope <= 0 {
                            finishedNotes.append(note)
                        }
                    } else {
                        let attackTime = Double(self.attack)
                        state.envelope = min(1.0, state.envelope + 1.0 / (sr * attackTime))
                    }

                    sample += Float(wave * state.envelope) * self.volume * 0.3

                    state.phase += phaseIncrement
                    if state.phase >= 1.0 { state.phase -= 1.0 }
                    self.activeNotes[note] = state
                }

                for note in finishedNotes {
                    self.activeNotes.removeValue(forKey: note)
                }
                self.noteLock.unlock()

                // Drum voices
                sample += self.processDrums(sampleRate: sr)

                // Clamp
                sample = max(-1.0, min(1.0, sample))

                for buffer in bufferList {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = sample
                }
            }

            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            print("Engine start error: \(error)")
        }
    }

    // MARK: - Note Control

    func noteOn(_ midiNote: Int) {
        noteLock.lock()
        activeNotes[midiNote] = NoteState()
        noteLock.unlock()
    }

    func noteOff(_ midiNote: Int) {
        noteLock.lock()
        if var state = activeNotes[midiNote] {
            state.releasing = true
            state.releaseStart = 0.0
            activeNotes[midiNote] = state
        }
        noteLock.unlock()
    }

    // MARK: - Drum Playback

    func playDrum(_ drum: DrumSound) {
        noteLock.lock()
        drumPhases[drum] = DrumState(phase: 0, time: 0, active: true)
        noteLock.unlock()
    }

    private func processDrums(sampleRate sr: Double) -> Float {
        var sample: Float = 0.0

        noteLock.lock()
        for (drum, var state) in drumPhases {
            guard state.active else { continue }

            let timeIncrement = 1.0 / sr

            switch drum {
            case .kick:
                // Pitch-dropping sine
                let freq = 150.0 * exp(-state.time * 8.0) + 40.0
                let env = exp(-state.time * 4.0)
                sample += Float(sin(state.phase * 2.0 * .pi) * env) * volume * 0.5
                state.phase += freq / sr
                if state.time > 0.5 { state.active = false }

            case .snare:
                // Noise + tone mix
                let tone = sin(state.phase * 2.0 * .pi * 200.0)
                let noise = Double.random(in: -1...1)
                let env = exp(-state.time * 10.0)
                sample += Float((tone * 0.3 + noise * 0.7) * env) * volume * 0.35
                state.phase += 1.0 / sr
                if state.time > 0.3 { state.active = false }

            case .hihat:
                // Filtered noise
                let noise = Double.random(in: -1...1)
                let env = exp(-state.time * 30.0)
                sample += Float(noise * env) * volume * 0.2
                if state.time > 0.15 { state.active = false }

            case .clap:
                // Burst noise
                let noise = Double.random(in: -1...1)
                let burstEnv = exp(-state.time * 15.0)
                let modulation = sin(state.time * 150.0) > 0 ? 1.0 : 0.6
                sample += Float(noise * burstEnv * modulation) * volume * 0.3
                if state.time > 0.2 { state.active = false }
            }

            state.time += timeIncrement
            drumPhases[drum] = state
        }
        noteLock.unlock()

        return sample
    }

    // MARK: - Helpers

    private func midiNoteToFrequency(_ note: Int) -> Double {
        440.0 * pow(2.0, Double(note - 69) / 12.0)
    }
}
