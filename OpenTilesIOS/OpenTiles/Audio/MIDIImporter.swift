import AudioToolbox
import Foundation

struct MIDIImporter {

    enum MIDIImportError: Error, LocalizedError {
        case failedToCreateSequence
        case failedToLoadFile(OSStatus)
        case noNotesFound

        var errorDescription: String? {
            switch self {
            case .failedToCreateSequence: return "Failed to create MIDI sequence"
            case .failedToLoadFile(let status): return "Failed to load MIDI file (error \(status))"
            case .noNotesFound: return "No notes found in MIDI file"
            }
        }
    }

    /// Import a MIDI file from a URL and return a Song ready for gameplay.
    static func importMIDI(from url: URL) throws -> Song {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        var sequence: MusicSequence?
        var status = NewMusicSequence(&sequence)
        guard status == noErr, let sequence = sequence else {
            throw MIDIImportError.failedToCreateSequence
        }
        defer { DisposeMusicSequence(sequence) }

        status = MusicSequenceFileLoad(sequence, url as CFURL, .midiType, .smf_ChannelsToTracks)
        guard status == noErr else {
            throw MIDIImportError.failedToLoadFile(status)
        }

        let bpm = extractTempo(from: sequence)

        // Extract notes from each track separately
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)

        var trackNotes: [[(beat: Double, midi: Int, dur: Double)]] = []

        for trackIndex in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, trackIndex, &track)
            guard let track = track else { continue }

            var notes: [(beat: Double, midi: Int, dur: Double)] = []
            var iterator: MusicEventIterator?
            NewMusicEventIterator(track, &iterator)
            guard let iterator = iterator else { continue }
            defer { DisposeMusicEventIterator(iterator) }

            var hasEvent: DarwinBoolean = false
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)

            while hasEvent.boolValue {
                var eventTime: MusicTimeStamp = 0
                var eventType: MusicEventType = 0
                var eventData: UnsafeRawPointer?
                var eventDataSize: UInt32 = 0

                MusicEventIteratorGetEventInfo(iterator, &eventTime, &eventType, &eventData, &eventDataSize)

                if eventType == kMusicEventType_MIDINoteMessage, let data = eventData {
                    let noteMessage = data.load(as: MIDINoteMessage.self)
                    let notePitch = Int(noteMessage.note)
                    let noteDuration = Double(noteMessage.duration)

                    if noteDuration > 0.01 && notePitch >= 21 && notePitch <= 108 {
                        notes.append((beat: Double(eventTime), midi: notePitch, dur: noteDuration))
                    }
                }

                MusicEventIteratorNextEvent(iterator)
                MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
            }

            if !notes.isEmpty {
                trackNotes.append(notes)
            }
        }

        guard !trackNotes.isEmpty else {
            throw MIDIImportError.noNotesFound
        }

        // Select melody track + collect background tracks
        let (melodyNotes, bgRawNotes) = selectMelodyAndBackground(trackNotes)

        var allNotes = melodyNotes
        allNotes.sort { $0.beat < $1.beat }

        // Bundle simultaneous melody notes into chords
        let chordNotes = bundleIntoChords(allNotes, maxNotesPerChord: 3)

        // Merge fast consecutive notes into arpeggio sequences
        let minGap: Double = 0.4
        var mergedNotes = mergeIntoArpeggios(chordNotes, minGap: minGap)

        // Cap very long notes
        mergedNotes = mergedNotes.map {
            var n = $0
            n.dur = min(n.dur, 4.0)
            return n
        }

        guard !mergedNotes.isEmpty else {
            throw MIDIImportError.noNotesFound
        }

        // Normalize: shift so first note starts at beat 0
        let firstBeat = mergedNotes[0].beat
        let beatOffset = firstBeat > 0 ? firstBeat : 0

        if beatOffset > 0 {
            mergedNotes = mergedNotes.map {
                var n = $0
                n.beat -= beatOffset
                n.arpeggio = n.arpeggio.map {
                    ArpeggioNote(midiNotes: $0.midiNotes, delayBeats: $0.delayBeats, duration: $0.duration)
                }
                return n
            }
        }

        // Convert melody to SongNotes
        let songNotes = assignColumnsWithArpeggio(mergedNotes)

        // Build background notes from non-melody tracks — bundle chords, shift by same offset
        var bgSorted = bgRawNotes
        bgSorted.sort { $0.beat < $1.beat }
        let bgChords = bundleIntoChords(bgSorted, maxNotesPerChord: 3)
        let backgroundNotes: [BackgroundNote] = bgChords.map {
            BackgroundNote(
                beatPosition: $0.beat - beatOffset,
                midiNotes: $0.midiNotes,
                duration: $0.dur
            )
        }.filter { $0.beatPosition >= 0 }

        let fileName = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        return Song(
            name: fileName,
            composer: "Imported",
            bpm: bpm,
            notes: songNotes,
            backgroundNotes: backgroundNotes
        )
    }

    /// Select the best melody track and collect all other tracks as background.
    /// Returns (melodyNotes, backgroundNotes).
    private static func selectMelodyAndBackground(
        _ trackNotes: [[(beat: Double, midi: Int, dur: Double)]]
    ) -> (melody: [(beat: Double, midi: Int, dur: Double)], background: [(beat: Double, midi: Int, dur: Double)]) {
        if trackNotes.count <= 1 {
            return (trackNotes.flatMap { $0 }, [])
        }

        struct TrackInfo {
            let index: Int
            let notes: [(beat: Double, midi: Int, dur: Double)]
            let avgPitch: Double
            let count: Int
        }

        let infos: [TrackInfo] = trackNotes.enumerated().map { idx, notes in
            let avg = notes.isEmpty ? 0 : Double(notes.map(\.midi).reduce(0, +)) / Double(notes.count)
            return TrackInfo(index: idx, notes: notes, avgPitch: avg, count: notes.count)
        }.filter { $0.count >= 10 }

        guard !infos.isEmpty else {
            return (trackNotes.flatMap { $0 }, [])
        }

        // Find melody track: highest average pitch with decent note count
        let melodyTrack = infos.max { a, b in
            let aScore = a.avgPitch + min(Double(a.count), 200) * 0.05
            let bScore = b.avgPitch + min(Double(b.count), 200) * 0.05
            return aScore < bScore
        }!

        // For background: only use bass/accompaniment tracks (low pitch),
        // not duplicate melody voices. Thin to one note per beat.
        let otherTracks = infos.filter { $0.index != melodyTrack.index }

        var bgNotes: [(beat: Double, midi: Int, dur: Double)] = []
        for track in otherTracks {
            // Skip tracks that are too similar to melody (duplicate voices)
            if abs(track.avgPitch - melodyTrack.avgPitch) < 10 { continue }

            // Thin: keep one note per beat
            var lastBeat: Double = -2
            for note in track.notes.sorted(by: { $0.beat < $1.beat }) {
                if note.beat - lastBeat >= 1.0 {
                    bgNotes.append(note)
                    lastBeat = note.beat
                }
            }
        }

        return (melodyTrack.notes, bgNotes)
    }

    /// Intermediate note with arpeggio data
    struct MergedNote {
        var beat: Double
        var midiNotes: [Int]
        var dur: Double
        var arpeggio: [ArpeggioNote]
    }

    /// Merge fast consecutive chord tiles into arpeggio sequences.
    /// Notes closer than minGap become arpeggio sub-notes of the preceding tile.
    private static func mergeIntoArpeggios(
        _ notes: [(beat: Double, midiNotes: [Int], dur: Double)],
        minGap: Double
    ) -> [MergedNote] {
        guard !notes.isEmpty else { return [] }

        var result: [MergedNote] = [
            MergedNote(beat: notes[0].beat, midiNotes: notes[0].midiNotes, dur: notes[0].dur, arpeggio: [])
        ]

        for i in 1..<notes.count {
            let gap = notes[i].beat - result.last!.beat
            if gap >= minGap {
                // Far enough apart — new tile
                result.append(MergedNote(
                    beat: notes[i].beat,
                    midiNotes: notes[i].midiNotes,
                    dur: notes[i].dur,
                    arpeggio: []
                ))
            } else {
                // Too close — merge as an arpeggio sub-note of the current tile
                let delayBeats = notes[i].beat - result[result.count - 1].beat
                result[result.count - 1].arpeggio.append(
                    ArpeggioNote(
                        midiNotes: notes[i].midiNotes,
                        delayBeats: delayBeats,
                        duration: notes[i].dur
                    )
                )
                // Extend the tile's total duration to cover the arpeggio
                let endBeat = notes[i].beat + notes[i].dur - result[result.count - 1].beat
                result[result.count - 1].dur = max(result[result.count - 1].dur, endBeat)
            }
        }

        return result
    }

    /// Assign columns to merged notes (with arpeggio data preserved)
    private static func assignColumnsWithArpeggio(_ notes: [MergedNote]) -> [SongNote] {
        var lastColumn = -1
        return notes.map { note in
            var col: Int
            repeat {
                col = Int.random(in: 0...3)
            } while col == lastColumn
            lastColumn = col
            return SongNote(
                beatPosition: note.beat,
                midiNotes: note.midiNotes,
                duration: note.dur,
                column: col,
                arpeggio: note.arpeggio
            )
        }
    }

    /// Bundle simultaneous notes into chord tiles.
    /// Notes within 0.05 beats of each other become one tile.
    /// Keeps melody (highest) + bass (lowest) + up to 1 inner voice for clean sound.
    private static func bundleIntoChords(
        _ notes: [(beat: Double, midi: Int, dur: Double)],
        maxNotesPerChord: Int
    ) -> [(beat: Double, midiNotes: [Int], dur: Double)] {
        guard !notes.isEmpty else { return [] }

        var groups: [[(beat: Double, midi: Int, dur: Double)]] = []
        var currentGroup: [(beat: Double, midi: Int, dur: Double)] = [notes[0]]

        for i in 1..<notes.count {
            if abs(notes[i].beat - currentGroup[0].beat) < 0.05 {
                currentGroup.append(notes[i])
            } else {
                groups.append(currentGroup)
                currentGroup = [notes[i]]
            }
        }
        groups.append(currentGroup)

        return groups.map { group in
            let beat = group[0].beat
            let dur = group.map(\.dur).max() ?? 1.0
            let uniquePitches = Array(Set(group.map(\.midi))).sorted()

            let selected: [Int]
            if uniquePitches.count <= maxNotesPerChord {
                selected = uniquePitches
            } else {
                // Keep melody (highest), bass (lowest), and fill with
                // notes that are well-spaced harmonically
                var picks: Set<Int> = []
                picks.insert(uniquePitches.last!)  // melody
                picks.insert(uniquePitches.first!) // bass

                // Add inner voices that are most spread out
                let remaining = uniquePitches.filter { !picks.contains($0) }
                for note in remaining {
                    if picks.count >= maxNotesPerChord { break }
                    // Only add if it's at least 3 semitones from existing picks
                    let tooClose = picks.contains { abs($0 - note) < 3 }
                    if !tooClose {
                        picks.insert(note)
                    }
                }

                selected = Array(picks).sorted()
            }

            return (beat: beat, midiNotes: selected, dur: dur)
        }
    }

    /// Extract tempo (BPM) from the MIDI tempo track.
    private static func extractTempo(from sequence: MusicSequence) -> Double {
        var tempoTrack: MusicTrack?
        MusicSequenceGetTempoTrack(sequence, &tempoTrack)
        guard let tempoTrack = tempoTrack else { return 120.0 }

        var iterator: MusicEventIterator?
        NewMusicEventIterator(tempoTrack, &iterator)
        guard let iterator = iterator else { return 120.0 }
        defer { DisposeMusicEventIterator(iterator) }

        var hasEvent: DarwinBoolean = false
        MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)

        while hasEvent.boolValue {
            var eventTime: MusicTimeStamp = 0
            var eventType: MusicEventType = 0
            var eventData: UnsafeRawPointer?
            var eventDataSize: UInt32 = 0

            MusicEventIteratorGetEventInfo(iterator, &eventTime, &eventType, &eventData, &eventDataSize)

            if eventType == kMusicEventType_ExtendedTempo, let data = eventData {
                let tempo = data.load(as: ExtendedTempoEvent.self)
                return tempo.bpm
            }

            MusicEventIteratorNextEvent(iterator)
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
        }

        return 120.0
    }
}
