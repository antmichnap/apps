import AVFoundation
import Foundation
import UIKit
import os

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

        var index: Int {
            switch self {
            case .kick:    return 0
            case .snare:   return 1
            case .hihat:   return 2
            case .openHat: return 3
            case .clap:    return 4
            case .tomHi:   return 5
            case .tomLo:   return 6
            case .shaker:  return 7
            }
        }

        static let count = 8
    }

    // MARK: - Published State

    @Published var waveform: Waveform = .saw
    @Published var volume: Float = 0.6
    @Published var attack: Float = 0.01
    @Published var release: Float = 0.3

    // Filter
    @Published var filterCutoff: Float = 1.0
    @Published var filterResonance: Float = 0.0

    // Reverb
    @Published var reverbMix: Float = 0.2
    @Published var reverbDecay: Float = 0.5

    // Delay
    @Published var delayMix: Float = 0.0
    @Published var delayTime: Float = 0.3
    @Published var delayFeedback: Float = 0.4

    // MARK: - Audio Properties

    private var engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private var sampleRate: Double = 48000.0

    // Lock-free state shared with audio thread via os_unfair_lock
    private var lock = os_unfair_lock()

    // Synth notes — fixed-size array avoids dictionary overhead on audio thread
    private static let maxNotes = 16
    private var noteSlots = [NoteSlot](repeating: NoteSlot(), count: AudioEngine.maxNotes)

    private struct NoteSlot {
        var active: Bool = false
        var midiNote: Int = 0
        var phase: Double = 0.0
        var envelope: Double = 0.0
        var releasing: Bool = false
        var releaseStart: Double = 0.0
    }

    // Drum state — fixed-size array indexed by DrumSound.index
    private var drumSlots = [DrumSlot](repeating: DrumSlot(), count: DrumSound.count)

    private struct DrumSlot {
        var phase: Double = 0.0
        var time: Double = 0.0
        var active: Bool = false
    }

    // Command queue — main thread appends, audio thread drains
    private enum AudioCommand {
        case noteOn(Int)
        case noteOff(Int)
        case playDrum(Int)
    }

    private var pendingCommands: [AudioCommand] = []

    // MARK: - Filter State

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

        delayBuffer = [Float](repeating: 0.0, count: Int(sr))
        delayWriteIndex = 0

        reverbBuffers = reverbLengths.map { [Float](repeating: 0.0, count: $0) }
        reverbIndices = [Int](repeating: 0, count: reverbLengths.count)

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }

            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            // Snapshot parameters once per buffer (no lock needed, atomic reads)
            let curWaveform = self.waveform
            let curVolume = self.volume
            let curAttack = Double(self.attack)
            let curRelease = Double(self.release)
            let curFilterCutoff = self.filterCutoff
            let curFilterResonance = self.filterResonance
            let curReverbMix = self.reverbMix
            let curReverbDecay = self.reverbDecay
            let curDelayMix = self.delayMix
            let curDelayTime = self.delayTime
            let curDelayFeedback = self.delayFeedback

            // Drain pending commands (lock held only for the swap)
            os_unfair_lock_lock(&self.lock)
            let commands = self.pendingCommands
            self.pendingCommands.removeAll()
            os_unfair_lock_unlock(&self.lock)

            // Apply commands — audio thread exclusively owns noteSlots/drumSlots
            for cmd in commands {
                switch cmd {
                case .noteOn(let midiNote):
                    var slotIdx = 0
                    for i in 0..<AudioEngine.maxNotes {
                        if !self.noteSlots[i].active {
                            slotIdx = i
                            break
                        }
                    }
                    self.noteSlots[slotIdx] = NoteSlot(active: true, midiNote: midiNote)
                case .noteOff(let midiNote):
                    for i in 0..<AudioEngine.maxNotes {
                        if self.noteSlots[i].active && self.noteSlots[i].midiNote == midiNote && !self.noteSlots[i].releasing {
                            self.noteSlots[i].releasing = true
                            self.noteSlots[i].releaseStart = 0.0
                        }
                    }
                case .playDrum(let index):
                    self.drumSlots[index] = DrumSlot(phase: 0, time: 0, active: true)
                }
            }

            // Local copies for processing
            var notes = self.noteSlots
            var drums = self.drumSlots

            // Process all frames
            for frame in 0..<frames {
                var sample: Float = 0.0

                // Synth voices
                for i in 0..<AudioEngine.maxNotes {
                    guard notes[i].active else { continue }

                    let frequency = 440.0 * pow(2.0, Double(notes[i].midiNote - 69) / 12.0)
                    let phaseIncrement = frequency / sr

                    var wave: Double
                    switch curWaveform {
                    case .sine:
                        wave = sin(notes[i].phase * 2.0 * .pi)
                    case .triangle:
                        wave = 2.0 * abs(2.0 * (notes[i].phase - floor(notes[i].phase + 0.5))) - 1.0
                    case .saw:
                        wave = 2.0 * (notes[i].phase - floor(notes[i].phase + 0.5))
                    case .square:
                        wave = notes[i].phase < 0.5 ? 1.0 : -1.0
                    case .wavetable:
                        let pos = notes[i].phase * Double(self.wavetableSize)
                        let idx = Int(pos) % self.wavetableSize
                        let frac = pos - floor(pos)
                        let next = (idx + 1) % self.wavetableSize
                        wave = self.wavetable[idx] * (1.0 - frac) + self.wavetable[next] * frac
                    }

                    if notes[i].releasing {
                        notes[i].releaseStart += 1.0 / sr
                        let progress = notes[i].releaseStart / curRelease
                        notes[i].envelope = max(0, 1.0 - progress)
                        if notes[i].envelope <= 0 {
                            notes[i].active = false
                        }
                    } else {
                        notes[i].envelope = min(1.0, notes[i].envelope + 1.0 / (sr * curAttack))
                    }

                    sample += Float(wave * notes[i].envelope) * curVolume * 0.3

                    notes[i].phase += phaseIncrement
                    if notes[i].phase >= 1.0 { notes[i].phase -= 1.0 }
                }

                // Filter
                let cutoffHz = 80.0 * pow(225.0, Double(curFilterCutoff))
                let f = 2.0 * sin(.pi * cutoffHz / sr)
                let q = 1.0 - Double(curFilterResonance) * 0.95
                let hp = Double(sample) - self.filterLP - q * self.filterBP
                self.filterBP += f * hp
                self.filterLP += f * self.filterBP
                sample = Float(self.filterLP)

                // Drums
                let timeInc = 1.0 / sr
                for d in 0..<DrumSound.count {
                    guard drums[d].active else { continue }
                    let t = drums[d].time

                    var ds: Float = 0.0
                    switch d {
                    case 0: // kick
                        let freq = 150.0 * exp(-t * 8.0) + 40.0
                        ds = Float(sin(drums[d].phase * 2.0 * .pi) * exp(-t * 4.0)) * curVolume * 0.5
                        drums[d].phase += freq / sr
                        if t > 0.5 { drums[d].active = false }
                    case 1: // snare
                        let tone = sin(drums[d].phase * 2.0 * .pi * 200.0)
                        let noise = Double.random(in: -1...1)
                        ds = Float((tone * 0.3 + noise * 0.7) * exp(-t * 10.0)) * curVolume * 0.35
                        drums[d].phase += 1.0 / sr
                        if t > 0.3 { drums[d].active = false }
                    case 2: // hihat
                        let noise = Double.random(in: -1...1)
                        ds = Float(noise * exp(-t * 30.0)) * curVolume * 0.2
                        if t > 0.15 { drums[d].active = false }
                    case 3: // open hat
                        let noise = Double.random(in: -1...1)
                        let ring = sin(drums[d].phase * 2.0 * .pi * 6000.0) * 0.3
                        ds = Float((noise * 0.7 + ring) * exp(-t * 6.0)) * curVolume * 0.2
                        drums[d].phase += 1.0 / sr
                        if t > 0.6 { drums[d].active = false }
                    case 4: // clap
                        let noise = Double.random(in: -1...1)
                        let mod = sin(t * 150.0) > 0 ? 1.0 : 0.6
                        ds = Float(noise * exp(-t * 15.0) * mod) * curVolume * 0.3
                        if t > 0.2 { drums[d].active = false }
                    case 5: // tom hi
                        let freq = 250.0 * exp(-t * 5.0) + 120.0
                        ds = Float(sin(drums[d].phase * 2.0 * .pi) * exp(-t * 6.0)) * curVolume * 0.4
                        drums[d].phase += freq / sr
                        if t > 0.4 { drums[d].active = false }
                    case 6: // tom lo
                        let freq = 120.0 * exp(-t * 4.0) + 60.0
                        ds = Float(sin(drums[d].phase * 2.0 * .pi) * exp(-t * 5.0)) * curVolume * 0.45
                        drums[d].phase += freq / sr
                        if t > 0.5 { drums[d].active = false }
                    case 7: // shaker
                        let noise = Double.random(in: -1...1)
                        let mod = abs(sin(t * 80.0 * .pi))
                        ds = Float(noise * mod * exp(-t * 12.0)) * curVolume * 0.15
                        if t > 0.2 { drums[d].active = false }
                    default:
                        break
                    }
                    sample += ds
                    drums[d].time += timeInc
                }

                // Delay
                if curDelayMix > 0.001 {
                    let delaySamples = Int(Double(curDelayTime) * sr)
                    if delaySamples > 0 && delaySamples < self.delayBuffer.count {
                        let readIdx = (self.delayWriteIndex - delaySamples + self.delayBuffer.count) % self.delayBuffer.count
                        let delayed = self.delayBuffer[readIdx]
                        let output = sample + delayed * curDelayMix
                        self.delayBuffer[self.delayWriteIndex] = sample + delayed * curDelayFeedback
                        self.delayWriteIndex = (self.delayWriteIndex + 1) % self.delayBuffer.count
                        sample = output
                    }
                }

                // Reverb
                if curReverbMix > 0.001 {
                    let decay = Float(0.3 + Double(curReverbDecay) * 0.65)
                    var combSum: Float = 0.0
                    for i in 0..<4 {
                        let idx = self.reverbIndices[i]
                        let delayed = self.reverbBuffers[i][idx]
                        self.reverbBuffers[i][idx] = sample + delayed * decay
                        self.reverbIndices[i] = (idx + 1) % self.reverbLengths[i]
                        combSum += delayed
                    }
                    combSum *= 0.25
                    var allpass = combSum
                    for i in 4..<6 {
                        let idx = self.reverbIndices[i]
                        let delayed = self.reverbBuffers[i][idx]
                        self.reverbBuffers[i][idx] = allpass + delayed * 0.5
                        allpass = delayed - allpass * 0.5
                        self.reverbIndices[i] = (idx + 1) % self.reverbLengths[i]
                    }
                    sample = sample * (1.0 - curReverbMix) + allpass * curReverbMix
                }

                sample = max(-1.0, min(1.0, sample))

                for buffer in bufferList {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = sample
                }
            }

            // Write back — audio thread exclusively owns this state, no lock needed
            self.noteSlots = notes
            self.drumSlots = drums

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

    // MARK: - Note Control

    func noteOn(_ midiNote: Int) {
        os_unfair_lock_lock(&lock)
        pendingCommands.append(.noteOn(midiNote))
        os_unfair_lock_unlock(&lock)
    }

    func noteOff(_ midiNote: Int) {
        os_unfair_lock_lock(&lock)
        pendingCommands.append(.noteOff(midiNote))
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Drum Playback

    func playDrum(_ drum: DrumSound) {
        os_unfair_lock_lock(&lock)
        pendingCommands.append(.playDrum(drum.index))
        os_unfair_lock_unlock(&lock)
    }
}
