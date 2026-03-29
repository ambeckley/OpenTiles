import AVFoundation
import Foundation

class ToneGenerator: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private let sampleRate: Double = 44100.0
    private var sourceNode: AVAudioSourceNode?
    private var activeNotes: [ActiveNote] = []
    private let noteLock = NSLock()
    private var sampleTime: Double = 0
    private var masterVolume: Double

    private struct ActiveNote {
        let frequency: Double
        let startSample: Double
        let duration: Double
        let fadeOut: Double
        var phase: Double = 0
        var removed: Bool = false
    }

    private let defaultFadeOut: Double = 0.15

    init(volume: Double = 1.0) {
        self.masterVolume = volume
        setupAudioSession()
        setupEngine()
    }

    func setVolume(_ volume: Double) {
        noteLock.lock()
        masterVolume = volume
        noteLock.unlock()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    private func setupEngine() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let buffer = ablPointer[0]
            let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
            let sr = self.sampleRate
            let vol = self.masterVolume

            self.noteLock.lock()
            let currentSample = self.sampleTime
            self.noteLock.unlock()

            for frame in 0..<Int(frameCount) {
                var sample: Float = 0
                let frameSample = currentSample + Double(frame)

                self.noteLock.lock()
                let noteCount = self.activeNotes.count
                for i in 0..<self.activeNotes.count {
                    let elapsed = (frameSample - self.activeNotes[i].startSample) / sr
                    guard elapsed >= 0 else { continue }

                    let dur = self.activeNotes[i].duration
                    let fadeOut = self.activeNotes[i].fadeOut

                    if elapsed > dur + fadeOut {
                        self.activeNotes[i].removed = true
                        continue
                    }

                    // Envelope: attack → decay → fade-out
                    let attack: Double = 0.004
                    var envelope: Double
                    if elapsed < attack {
                        envelope = elapsed / attack
                    } else if elapsed < dur {
                        // Piano-like decay — steeper so it's quiet by note end
                        envelope = exp(-(elapsed - attack) * 5.0)
                    } else {
                        // Smooth fade to zero over fadeOut duration
                        let fadeElapsed = elapsed - dur
                        let fadeRatio = max(0, 1.0 - fadeElapsed / fadeOut)
                        // Quadratic ease-out for smoother fade
                        envelope = exp(-(dur - attack) * 5.0) * fadeRatio * fadeRatio
                    }

                    // Phase-accurate synthesis
                    let phaseInc = self.activeNotes[i].frequency / sr
                    self.activeNotes[i].phase += phaseInc
                    let p = self.activeNotes[i].phase

                    // Rich piano tone: fundamental + harmonics
                    let wave = sin(2.0 * .pi * p)
                        + 0.4 * sin(2.0 * .pi * p * 2.0)
                        + 0.15 * sin(2.0 * .pi * p * 3.0)
                        + 0.06 * sin(2.0 * .pi * p * 4.0)

                    let gain = (0.22 * vol) / max(1.0, sqrt(Double(noteCount)))
                    sample += Float(envelope * gain * wave)
                }
                self.noteLock.unlock()

                sample = max(-0.95, min(0.95, sample))
                ptr[frame] = sample
            }

            self.noteLock.lock()
            self.sampleTime += Double(frameCount)
            self.activeNotes.removeAll { $0.removed }
            self.noteLock.unlock()

            return noErr
        }

        audioEngine.attach(sourceNode!)
        audioEngine.connect(sourceNode!, to: audioEngine.mainMixerNode, format: format)

        do {
            try audioEngine.start()
        } catch {
            print("Audio engine start failed: \(error)")
        }
    }

    func playNote(midiNote: Int, duration: Double = 0.8) {
        playNotes(midiNotes: [midiNote], duration: duration)
    }

    func playNotes(midiNotes: [Int], duration: Double = 0.8) {
        noteLock.lock()
        let now = sampleTime
        for midi in midiNotes {
            activeNotes.append(ActiveNote(
                frequency: MIDINote.frequency(for: midi),
                startSample: now,
                duration: duration,
                fadeOut: defaultFadeOut
            ))
        }
        noteLock.unlock()
    }

    func playNotesDelayed(midiNotes: [Int], delaySeconds: Double, duration: Double) {
        noteLock.lock()
        let futureStart = sampleTime + delaySeconds * sampleRate
        for midi in midiNotes {
            activeNotes.append(ActiveNote(
                frequency: MIDINote.frequency(for: midi),
                startSample: futureStart,
                duration: duration,
                fadeOut: defaultFadeOut
            ))
        }
        noteLock.unlock()
    }

    func playWrongNote() {
        noteLock.lock()
        let now = sampleTime
        for midi in [60, 61, 66] {
            activeNotes.append(ActiveNote(
                frequency: MIDINote.frequency(for: midi),
                startSample: now,
                duration: 0.4,
                fadeOut: 0.05
            ))
        }
        noteLock.unlock()
    }

    func stop() {
        noteLock.lock()
        let now = sampleTime
        for i in activeNotes.indices {
            let elapsed = (now - activeNotes[i].startSample) / sampleRate
            if elapsed >= 0 && !activeNotes[i].removed {
                activeNotes[i] = ActiveNote(
                    frequency: activeNotes[i].frequency,
                    startSample: activeNotes[i].startSample,
                    duration: max(0, elapsed),
                    fadeOut: 0.02,
                    phase: activeNotes[i].phase
                )
            }
        }
        noteLock.unlock()
    }

    deinit {
        audioEngine.stop()
    }
}
