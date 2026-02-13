import AVFoundation
import Foundation
import UIKit

/// Core audio engine handling synthesis and drum playback
final class AudioEngine: ObservableObject {

    // MARK: - Types

    enum Waveform: String, CaseIterable, Identifiable {
        case sine = "Sine"
        case triangle = "Triangle"
        case saw = "Saw"
        case square = "Square"
        case wavetable = "Wavetable"

        var id: String { rawValue }
    }

    enum DrumSound: String, CaseIterable, Identifiable {
        case kick = "Kick"
        case snare = "Snare"
        case hihat = "Hi-Hat"
        case openHat = "Open Hat"
        case clap = "Clap"
        case tomHi = "Tom Hi"
        case tomLo = "Tom Lo"
        case shaker = "Shaker"

        var id: String { rawValue }
    }

    // MARK: - Published State

    @Published var waveform: Waveform = .saw
    @Published var volume: Float = 0.6
    @Published var attack: Float = 0.01
    @Published var release: Float = 0.3

    // Filter
    @Published var filterCutoff: Float = 1.0   // 0..1, mapped to freq
    @Published var filterResonance: Float = 0.0 // 0..1

    // Reverb
    @Published var reverbMix: Float = 0.2       // 0..1
    @Published var reverbDecay: Float = 0.5     // 0..1

    // Delay
    @Published var delayMix: Float = 0.0        // 0..1
    @Published var delayTime: Float = 0.3       // seconds 0.05..1.0
    @Published var delayFeedback: Float = 0.4   // 0..0.9

    // MARK: - Audio Properties

    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private var sampleRate: Double = 48000.0
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

    // MARK: - Filter State (simple one-pole low-pass)

    private var filterLP: Double = 0.0
    private var filterBP: Double = 0.0

    // MARK: - Delay Buffer

    private var delayBuffer: [Float] = []
    private var delayWriteIndex: Int = 0

    // MARK: - Reverb (simple Schroeder)

    private var reverbBuffers: [[Float]] = []
    private var reverbIndices: [Int] = []
    private let reverbLengths = [1557, 1617, 1491, 1422, 225, 556]

    // MARK: - Wavetable

    private var wavetable: [Double] = []
    private let wavetableSize = 2048

    // MARK: - Init

    init() {
        generateWavetable()
        setupAudioSession()
        setupEngine()
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func generateWavetable() {
        wavetable = (0..<wavetableSize).map { i in
            let phase = Double(i) / Double(wavetableSize)
            let fundamental = sin(phase * 2.0 * .pi)
            let second = sin(phase * 4.0 * .pi) * 0.5
            let third = sin(phase * 6.0 * .pi) * 0.3
            let fifth = sin(phase * 10.0 * .pi) * 0.15
            let distortion = sin(phase * phase * 8.0 * .pi) * 0.2
            return (fundamental + second + third + fifth + distortion) / 2.15
        }
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            // Use the device's actual sample rate
            sampleRate = session.sampleRate
            if sampleRate <= 0 { sampleRate = 48000.0 }
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                startEngineIfNeeded()
            } catch {
                print("Failed to reactivate audio session: \(error)")
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        startEngineIfNeeded()
    }

    @objc private func handleAppDidBecomeActive() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to reactivate audio session: \(error)")
        }
        startEngineIfNeeded()
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("Engine restart error: \(error)")
        }
    }

    private func setupEngine() {
        let sr = sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!

        // Initialize delay buffer (max 1 second)
        delayBuffer = [Float](repeating: 0.0, count: Int(sr))
        delayWriteIndex = 0

        // Initialize reverb buffers
        reverbBuffers = reverbLengths.map { [Float](repeating: 0.0, count: $0) }
        reverbIndices = [Int](repeating: 0, count: reverbLengths.count)

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
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
                    case .triangle:
                        wave = 2.0 * abs(2.0 * (state.phase - floor(state.phase + 0.5))) - 1.0
                    case .saw:
                        wave = 2.0 * (state.phase - floor(state.phase + 0.5))
                    case .square:
                        wave = state.phase < 0.5 ? 1.0 : -1.0
                    case .wavetable:
                        let pos = state.phase * Double(self.wavetableSize)
                        let idx = Int(pos) % self.wavetableSize
                        let frac = pos - floor(pos)
                        let next = (idx + 1) % self.wavetableSize
                        wave = self.wavetable[idx] * (1.0 - frac) + self.wavetable[next] * frac
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

                // Apply filter to synth signal
                sample = self.applyFilter(sample, sampleRate: sr)

                // Drum voices (unfiltered)
                sample += self.processDrums(sampleRate: sr)

                // Apply delay
                sample = self.applyDelay(sample, sampleRate: sr)

                // Apply reverb
                sample = self.applyReverb(sample)

                // Clamp
                sample = max(-1.0, min(1.0, sample))

                for buffer in bufferList {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = sample
                }
            }

            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            print("Audio engine started at \(sr) Hz")
        } catch {
            print("Engine start error: \(error)")
        }
    }

    // MARK: - Filter (State Variable Filter)

    private func applyFilter(_ input: Float, sampleRate sr: Double) -> Float {
        let cutoffHz = 80.0 * pow(225.0, Double(filterCutoff))
        let f = 2.0 * sin(.pi * cutoffHz / sr)
        let q = 1.0 - Double(filterResonance) * 0.95

        let hp = Double(input) - filterLP - q * filterBP
        filterBP += f * hp
        filterLP += f * filterBP

        return Float(filterLP)
    }

    // MARK: - Delay

    private func applyDelay(_ input: Float, sampleRate sr: Double) -> Float {
        guard delayMix > 0.001 else { return input }

        let delaySamples = Int(Double(delayTime) * sr)
        guard delaySamples > 0 && delaySamples < delayBuffer.count else { return input }

        let readIndex = (delayWriteIndex - delaySamples + delayBuffer.count) % delayBuffer.count
        let delayed = delayBuffer[readIndex]

        let output = input + delayed * delayMix
        delayBuffer[delayWriteIndex] = input + delayed * delayFeedback
        delayWriteIndex = (delayWriteIndex + 1) % delayBuffer.count

        return output
    }

    // MARK: - Reverb (Schroeder)

    private func applyReverb(_ input: Float) -> Float {
        guard reverbMix > 0.001 else { return input }

        let decay = 0.3 + Double(reverbDecay) * 0.65

        // 4 comb filters
        var combSum: Float = 0.0
        for i in 0..<4 {
            let idx = reverbIndices[i]
            let delayed = reverbBuffers[i][idx]
            reverbBuffers[i][idx] = input + delayed * Float(decay)
            reverbIndices[i] = (idx + 1) % reverbLengths[i]
            combSum += delayed
        }
        combSum *= 0.25

        // 2 allpass filters
        var allpass = combSum
        for i in 4..<6 {
            let idx = reverbIndices[i]
            let delayed = reverbBuffers[i][idx]
            let newVal = allpass + delayed * 0.5
            reverbBuffers[i][idx] = newVal
            allpass = delayed - allpass * 0.5
            reverbIndices[i] = (idx + 1) % reverbLengths[i]
        }

        return input * (1.0 - reverbMix) + allpass * reverbMix
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
                let freq = 150.0 * exp(-state.time * 8.0) + 40.0
                let env = exp(-state.time * 4.0)
                sample += Float(sin(state.phase * 2.0 * .pi) * env) * volume * 0.5
                state.phase += freq / sr
                if state.time > 0.5 { state.active = false }

            case .snare:
                let tone = sin(state.phase * 2.0 * .pi * 200.0)
                let noise = Double.random(in: -1...1)
                let env = exp(-state.time * 10.0)
                sample += Float((tone * 0.3 + noise * 0.7) * env) * volume * 0.35
                state.phase += 1.0 / sr
                if state.time > 0.3 { state.active = false }

            case .hihat:
                let noise = Double.random(in: -1...1)
                let env = exp(-state.time * 30.0)
                sample += Float(noise * env) * volume * 0.2
                if state.time > 0.15 { state.active = false }

            case .openHat:
                let noise = Double.random(in: -1...1)
                let env = exp(-state.time * 6.0)
                let ring = sin(state.phase * 2.0 * .pi * 6000.0) * 0.3
                sample += Float((noise * 0.7 + ring) * env) * volume * 0.2
                state.phase += 1.0 / sr
                if state.time > 0.6 { state.active = false }

            case .clap:
                let noise = Double.random(in: -1...1)
                let burstEnv = exp(-state.time * 15.0)
                let modulation = sin(state.time * 150.0) > 0 ? 1.0 : 0.6
                sample += Float(noise * burstEnv * modulation) * volume * 0.3
                if state.time > 0.2 { state.active = false }

            case .tomHi:
                let freq = 250.0 * exp(-state.time * 5.0) + 120.0
                let env = exp(-state.time * 6.0)
                sample += Float(sin(state.phase * 2.0 * .pi) * env) * volume * 0.4
                state.phase += freq / sr
                if state.time > 0.4 { state.active = false }

            case .tomLo:
                let freq = 120.0 * exp(-state.time * 4.0) + 60.0
                let env = exp(-state.time * 5.0)
                sample += Float(sin(state.phase * 2.0 * .pi) * env) * volume * 0.45
                state.phase += freq / sr
                if state.time > 0.5 { state.active = false }

            case .shaker:
                let noise = Double.random(in: -1...1)
                let mod = abs(sin(state.time * 80.0 * .pi))
                let env = exp(-state.time * 12.0)
                sample += Float(noise * mod * env) * volume * 0.15
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
