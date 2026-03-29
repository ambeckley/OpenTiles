import Foundation

/// A sub-note within an arpeggio sequence — played at a delay after the tile is tapped
struct ArpeggioNote: Codable {
    let midiNotes: [Int]
    let delayBeats: Double
    let duration: Double
}

struct SongNote: Identifiable, Codable {
    let id: UUID
    let beatPosition: Double   // when in the song (in beats, starting from 0)
    let midiNotes: [Int]       // primary MIDI note numbers to play on tap
    let duration: Double       // total length in beats
    let column: Int            // lane 0-3
    let arpeggio: [ArpeggioNote] // additional notes played as a sequence after tap

    /// Primary MIDI note (highest pitch, used for display/melody reference)
    var midiNote: Int { midiNotes.max() ?? 60 }

    init(beatPosition: Double, midiNotes: [Int], duration: Double, column: Int, arpeggio: [ArpeggioNote] = []) {
        self.id = UUID()
        self.beatPosition = beatPosition
        self.midiNotes = midiNotes
        self.duration = duration
        self.column = column
        self.arpeggio = arpeggio
    }
}

/// A background note that plays automatically (not tapped by the player)
struct BackgroundNote: Codable {
    let beatPosition: Double
    let midiNotes: [Int]
    let duration: Double
}

struct Song: Identifiable, Codable {
    let id: UUID
    let name: String
    let composer: String
    let bpm: Double
    let notes: [SongNote]
    let backgroundNotes: [BackgroundNote]  // auto-played accompaniment

    init(name: String, composer: String, bpm: Double, notes: [SongNote], backgroundNotes: [BackgroundNote] = []) {
        self.id = UUID()
        self.name = name
        self.composer = composer
        self.bpm = bpm
        self.notes = notes
        self.backgroundNotes = backgroundNotes
    }

    var totalBeats: Double {
        guard let last = notes.last else { return 0 }
        return last.beatPosition + last.duration
    }

    /// Create a new song with notes duplicated N times sequentially
    func looped(times: Int) -> Song {
        guard times > 1 else { return self }
        let total = totalBeats
        var allNotes: [(beat: Double, midiNotes: [Int], dur: Double)] = []
        for loop in 0..<times {
            let offset = Double(loop) * total
            for note in notes {
                allNotes.append((
                    beat: note.beatPosition + offset,
                    midiNotes: note.midiNotes,
                    dur: note.duration
                ))
            }
        }
        let songNotes = SongLibrary.assignColumnsChords(to: allNotes)

        // Loop background notes too
        var allBg: [BackgroundNote] = []
        for loop in 0..<times {
            let offset = Double(loop) * total
            for bg in backgroundNotes {
                allBg.append(BackgroundNote(
                    beatPosition: bg.beatPosition + offset,
                    midiNotes: bg.midiNotes,
                    duration: bg.duration
                ))
            }
        }

        return Song(name: name, composer: composer, bpm: bpm, notes: songNotes, backgroundNotes: allBg)
    }
}

// MARK: - Game Settings

enum GameMode: String, CaseIterable, Identifiable {
    case normal
    case endless
    case practice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return String(localized: "Normal")
        case .endless: return String(localized: "Endless")
        case .practice: return String(localized: "Practice")
        }
    }

    var description: String {
        switch self {
        case .normal: return String(localized: "Play through with scoring")
        case .endless: return String(localized: "Song loops forever")
        case .practice: return String(localized: "No penalties, play at your pace")
        }
    }

    var icon: String {
        switch self {
        case .normal: return "play.circle"
        case .endless: return "infinity"
        case .practice: return "graduationcap"
        }
    }
}

struct GameSettings {
    var bpmMultiplier: Double = 1.0
    var loopCount: Int = 1  // 0 = endless
    var mode: GameMode = .normal
    var backgroundVolume: Double = 0.45
}

// MARK: - MIDI Note Constants
enum MIDINote {
    // Octave 3
    static let C3  = 48
    static let D3  = 50
    static let E3  = 52
    static let F3  = 53
    static let Fs3 = 54
    static let G3  = 55
    static let A3  = 57
    static let Bb3 = 58
    static let B3  = 59
    // Octave 4
    static let C4  = 60
    static let Cs4 = 61
    static let D4  = 62
    static let Eb4 = 63
    static let E4  = 64
    static let F4  = 65
    static let Fs4 = 66
    static let G4  = 67
    static let Ab4 = 68
    static let A4  = 69
    static let Bb4 = 70
    static let B4  = 71
    // Octave 5
    static let C5  = 72
    static let Cs5 = 73
    static let D5  = 74
    static let Eb5 = 75
    static let E5  = 76
    static let F5  = 77
    static let Fs5 = 78
    static let G5  = 79
    static let A5  = 81
    static let B5  = 83
    // Octave 6
    static let C6  = 84

    static func frequency(for midiNote: Int) -> Double {
        440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
    }
}

// MARK: - Song Library
struct SongLibrary {
    static let songs: [Song] = [
        twinkleTwinkle,
        odeToJoy,
        maryHadALittleLamb,
        happyBirthday,
        londonBridge,
        rowRowRow,
        jingleBells,
        auClair,
        alouette,
        furElise,
        minuetInG,
        canCanMelody,
        williamTell,
        blueDanube,
        swanLake,
        greensleeves,
        scarborough,
    ]

    // Helper to auto-assign columns — takes single-note tuples
    static func assignColumns(to rawNotes: [(beat: Double, midi: Int, dur: Double)]) -> [SongNote] {
        let asChords = rawNotes.map { (beat: $0.beat, midiNotes: [$0.midi], dur: $0.dur) }
        return assignColumnsChords(to: asChords)
    }

    // Helper to auto-assign columns — takes multi-note (chord) tuples
    static func assignColumnsChords(to rawNotes: [(beat: Double, midiNotes: [Int], dur: Double)]) -> [SongNote] {
        var lastColumn = -1
        return rawNotes.map { note in
            var col: Int
            repeat {
                col = Int.random(in: 0...3)
            } while col == lastColumn
            lastColumn = col
            return SongNote(
                beatPosition: note.beat,
                midiNotes: note.midiNotes,
                duration: note.dur,
                column: col
            )
        }
    }

    // MARK: - Easy

    static let twinkleTwinkle = Song(
        name: "Twinkle Twinkle Little Star",
        composer: "Traditional",
        bpm: 100,
        notes: assignColumns(to: [
            (0, C4, 1), (1, C4, 1), (2, G4, 1), (3, G4, 1),
            (4, A4, 1), (5, A4, 1), (6, G4, 2),
            (8, F4, 1), (9, F4, 1), (10, E4, 1), (11, E4, 1),
            (12, D4, 1), (13, D4, 1), (14, C4, 2),
            (16, G4, 1), (17, G4, 1), (18, F4, 1), (19, F4, 1),
            (20, E4, 1), (21, E4, 1), (22, D4, 2),
            (24, G4, 1), (25, G4, 1), (26, F4, 1), (27, F4, 1),
            (28, E4, 1), (29, E4, 1), (30, D4, 2),
            (32, C4, 1), (33, C4, 1), (34, G4, 1), (35, G4, 1),
            (36, A4, 1), (37, A4, 1), (38, G4, 2),
            (40, F4, 1), (41, F4, 1), (42, E4, 1), (43, E4, 1),
            (44, D4, 1), (45, D4, 1), (46, C4, 2),
        ])
    )

    static let odeToJoy = Song(
        name: "Ode to Joy",
        composer: "Beethoven",
        bpm: 108,
        notes: assignColumns(to: [
            (0, E4, 1), (1, E4, 1), (2, F4, 1), (3, G4, 1),
            (4, G4, 1), (5, F4, 1), (6, E4, 1), (7, D4, 1),
            (8, C4, 1), (9, C4, 1), (10, D4, 1), (11, E4, 1),
            (12, E4, 1.5), (13.5, D4, 0.5), (14, D4, 2),
            (16, E4, 1), (17, E4, 1), (18, F4, 1), (19, G4, 1),
            (20, G4, 1), (21, F4, 1), (22, E4, 1), (23, D4, 1),
            (24, C4, 1), (25, C4, 1), (26, D4, 1), (27, E4, 1),
            (28, D4, 1.5), (29.5, C4, 0.5), (30, C4, 2),
        ])
    )

    static let maryHadALittleLamb = Song(
        name: "Mary Had a Little Lamb",
        composer: "Traditional",
        bpm: 110,
        notes: assignColumns(to: [
            (0, E4, 1), (1, D4, 1), (2, C4, 1), (3, D4, 1),
            (4, E4, 1), (5, E4, 1), (6, E4, 2),
            (8, D4, 1), (9, D4, 1), (10, D4, 2),
            (12, E4, 1), (13, G4, 1), (14, G4, 2),
            (16, E4, 1), (17, D4, 1), (18, C4, 1), (19, D4, 1),
            (20, E4, 1), (21, E4, 1), (22, E4, 1), (23, E4, 1),
            (24, D4, 1), (25, D4, 1), (26, E4, 1), (27, D4, 1),
            (28, C4, 4),
        ])
    )

    static let happyBirthday = Song(
        name: "Happy Birthday",
        composer: "Traditional",
        bpm: 100,
        notes: assignColumns(to: [
            (0, G4, 0.5), (0.5, G4, 0.5), (1, A4, 1), (2, G4, 1),
            (3, C5, 1), (4, B4, 2),
            (6, G4, 0.5), (6.5, G4, 0.5), (7, A4, 1), (8, G4, 1),
            (9, D5, 1), (10, C5, 2),
            (12, G4, 0.5), (12.5, G4, 0.5), (13, G5, 1), (14, E5, 1),
            (15, C5, 1), (16, B4, 1), (17, A4, 2),
            (19, F5, 0.5), (19.5, F5, 0.5), (20, E5, 1), (21, C5, 1),
            (22, D5, 1), (23, C5, 2),
        ])
    )

    static let londonBridge = Song(
        name: "London Bridge",
        composer: "Traditional",
        bpm: 120,
        notes: assignColumns(to: [
            (0, G4, 1.5), (1.5, A4, 0.5), (2, G4, 1), (3, F4, 1),
            (4, E4, 1), (5, F4, 1), (6, G4, 2),
            (8, D4, 1), (9, E4, 1), (10, F4, 2),
            (12, E4, 1), (13, F4, 1), (14, G4, 2),
            (16, G4, 1.5), (17.5, A4, 0.5), (18, G4, 1), (19, F4, 1),
            (20, E4, 1), (21, F4, 1), (22, G4, 2),
            (24, D4, 2), (26, G4, 1), (27, E4, 1),
            (28, C4, 4),
        ])
    )

    static let rowRowRow = Song(
        name: "Row Row Row Your Boat",
        composer: "Traditional",
        bpm: 100,
        notes: assignColumns(to: [
            (0, C4, 1.5), (1.5, C4, 0.5), (2, C4, 1), (3, D4, 0.5), (3.5, E4, 0.5),
            (4, E4, 1), (5, D4, 0.5), (5.5, E4, 0.5), (6, F4, 1), (7, G4, 1),
            (8, C5, 0.5), (8.5, C5, 0.5), (9, C5, 0.5),
            (9.5, G4, 0.5), (10, G4, 0.5), (10.5, G4, 0.5),
            (11, E4, 0.5), (11.5, E4, 0.5), (12, E4, 0.5),
            (12.5, C4, 0.5), (13, C4, 0.5), (13.5, C4, 0.5),
            (14, G4, 1), (15, F4, 0.5), (15.5, E4, 0.5),
            (16, D4, 1), (17, C4, 2),
        ])
    )

    static let jingleBells = Song(
        name: "Jingle Bells",
        composer: "Pierpont",
        bpm: 120,
        notes: assignColumns(to: [
            // Jingle bells, jingle bells, jingle all the way
            (0, E4, 1), (1, E4, 1), (2, E4, 2),
            (4, E4, 1), (5, E4, 1), (6, E4, 2),
            (8, E4, 1), (9, G4, 1), (10, C4, 1.5), (11.5, D4, 0.5),
            (12, E4, 4),
            // Oh what fun it is to ride
            (16, F4, 1), (17, F4, 1), (18, F4, 1.5), (19.5, F4, 0.5),
            (20, F4, 1), (21, E4, 1), (22, E4, 1), (23, E4, 0.5), (23.5, E4, 0.5),
            (24, E4, 1), (25, D4, 1), (26, D4, 1), (27, E4, 1),
            (28, D4, 2), (30, G4, 2),
        ])
    )

    static let auClair = Song(
        name: "Au Clair de la Lune",
        composer: "Traditional French",
        bpm: 96,
        notes: assignColumns(to: [
            (0, C4, 1), (1, C4, 1), (2, C4, 1), (3, D4, 1),
            (4, E4, 2), (6, D4, 2),
            (8, C4, 1), (9, E4, 1), (10, D4, 1), (11, D4, 1),
            (12, C4, 4),
            (16, C4, 1), (17, C4, 1), (18, C4, 1), (19, D4, 1),
            (20, E4, 2), (22, D4, 2),
            (24, C4, 1), (25, E4, 1), (26, D4, 1), (27, D4, 1),
            (28, C4, 4),
        ])
    )

    static let alouette = Song(
        name: "Alouette",
        composer: "Traditional French",
        bpm: 112,
        notes: assignColumns(to: [
            (0, C4, 1), (1, F4, 0.5), (1.5, F4, 0.5), (2, F4, 1), (3, G4, 1),
            (4, A4, 0.5), (4.5, A4, 0.5), (5, A4, 1), (6, G4, 2),
            (8, F4, 1), (9, G4, 0.5), (9.5, A4, 0.5), (10, G4, 1), (11, F4, 1),
            (12, E4, 1), (13, D4, 1), (14, C4, 2),
            (16, C4, 1), (17, F4, 0.5), (17.5, F4, 0.5), (18, F4, 1), (19, G4, 1),
            (20, A4, 0.5), (20.5, A4, 0.5), (21, A4, 1), (22, G4, 2),
            (24, F4, 1), (25, G4, 0.5), (25.5, A4, 0.5), (26, G4, 1), (27, F4, 1),
            (28, E4, 1), (29, D4, 1), (30, C4, 2),
        ])
    )

    // MARK: - Medium

    static let furElise = Song(
        name: "Fur Elise",
        composer: "Beethoven",
        bpm: 80,
        notes: assignColumns(to: [
            // Main theme
            (0, E5, 0.5), (0.5, Eb5, 0.5),
            (1, E5, 0.5), (1.5, Eb5, 0.5),
            (2, E5, 0.5), (2.5, B4, 0.5),
            (3, D5, 0.5), (3.5, C5, 0.5),
            (4, A4, 1.5),
            (5.5, C4, 0.5), (6, E4, 0.5), (6.5, A4, 0.5),
            (7, B4, 1.5),
            (8.5, E4, 0.5), (9, Ab4, 0.5), (9.5, B4, 0.5),
            (10, C5, 1.5),
            (11.5, E4, 0.5),
            // Repeat theme
            (12, E5, 0.5), (12.5, Eb5, 0.5),
            (13, E5, 0.5), (13.5, Eb5, 0.5),
            (14, E5, 0.5), (14.5, B4, 0.5),
            (15, D5, 0.5), (15.5, C5, 0.5),
            (16, A4, 1.5),
            (17.5, C4, 0.5), (18, E4, 0.5), (18.5, A4, 0.5),
            (19, B4, 1.5),
            (20.5, E4, 0.5), (21, C5, 0.5), (21.5, B4, 0.5),
            (22, A4, 2),
        ])
    )

    static let minuetInG = Song(
        name: "Minuet in G",
        composer: "Bach",
        bpm: 108,
        notes: assignColumns(to: [
            (0, D5, 1), (1, G4, 0.5), (1.5, A4, 0.5), (2, B4, 0.5), (2.5, C5, 0.5),
            (3, D5, 1), (4, G4, 1), (5, G4, 1),
            (6, E5, 1), (7, C5, 0.5), (7.5, D5, 0.5), (8, E5, 0.5), (8.5, Fs5, 0.5),
            (9, G5, 1), (10, G4, 1), (11, G4, 1),
            (12, C5, 1), (13, D5, 0.5), (13.5, C5, 0.5), (14, B4, 0.5), (14.5, A4, 0.5),
            (15, B4, 1), (16, C5, 0.5), (16.5, B4, 0.5), (17, A4, 0.5), (17.5, G4, 0.5),
            (18, Fs4, 1), (19, G4, 0.5), (19.5, A4, 0.5), (20, B4, 0.5), (20.5, G4, 0.5),
            (21, A4, 3),
        ])
    )

    static let canCanMelody = Song(
        name: "Can-Can",
        composer: "Offenbach",
        bpm: 132,
        notes: assignColumns(to: [
            (0, E4, 0.5), (0.5, F4, 0.5), (1, G4, 0.5), (1.5, G4, 0.5),
            (2, A4, 0.5), (2.5, G4, 0.5), (3, A4, 0.5), (3.5, G4, 0.5),
            (4, E4, 0.5), (4.5, F4, 0.5), (5, G4, 0.5), (5.5, G4, 0.5),
            (6, A4, 0.5), (6.5, G4, 0.5), (7, A4, 0.5), (7.5, G4, 0.5),
            (8, E4, 0.5), (8.5, G4, 0.5), (9, C5, 0.5), (9.5, G4, 0.5),
            (10, E5, 0.5), (10.5, C5, 0.5), (11, E5, 0.5), (11.5, C5, 0.5),
            (12, D5, 0.5), (12.5, E5, 0.5), (13, D5, 0.5), (13.5, C5, 0.5),
            (14, B4, 0.5), (14.5, C5, 0.5), (15, D5, 2),
        ])
    )

    static let williamTell = Song(
        name: "William Tell Overture",
        composer: "Rossini",
        bpm: 152,
        notes: assignColumns(to: [
            (0, G4, 0.5), (0.5, G4, 0.5), (1, G4, 0.5), (1.5, G4, 0.5),
            (2, G4, 0.5), (2.5, E4, 0.5), (3, G4, 2),
            (5, G4, 0.5), (5.5, G4, 0.5), (6, G4, 0.5), (6.5, G4, 0.5),
            (7, G4, 0.5), (7.5, E4, 0.5), (8, G4, 2),
            (10, G4, 0.5), (10.5, G4, 0.5), (11, G4, 0.5), (11.5, A4, 0.5),
            (12, B4, 0.5), (12.5, B4, 0.5), (13, B4, 0.5), (13.5, C5, 0.5),
            (14, D5, 1), (15, D5, 1),
            (16, D5, 0.5), (16.5, B4, 0.5), (17, G4, 0.5), (17.5, B4, 0.5),
            (18, D5, 2),
            (20, D5, 0.5), (20.5, B4, 0.5), (21, G4, 0.5), (21.5, B4, 0.5),
            (22, D5, 2),
        ])
    )

    static let blueDanube = Song(
        name: "The Blue Danube",
        composer: "Strauss",
        bpm: 108,
        notes: assignColumns(to: [
            // Waltz theme
            (0, D4, 2), (2, D4, 1),
            (3, Fs4, 2), (5, Fs4, 1),
            (6, A4, 2), (8, A4, 1),
            (9, D5, 3),
            (12, D5, 3),
            (15, Cs5, 2), (17, A4, 1),
            (18, Cs5, 3),
            (21, Cs5, 3),
            (24, B4, 2), (26, G4, 1),
            (27, B4, 3),
            (30, B4, 3),
            (33, A4, 2), (35, Fs4, 1),
            (36, D4, 2), (38, D4, 1),
        ])
    )

    static let swanLake = Song(
        name: "Swan Lake Theme",
        composer: "Tchaikovsky",
        bpm: 88,
        notes: assignColumns(to: [
            (0, A4, 2), (2, B4, 1),
            (3, C5, 1.5), (4.5, B4, 0.5), (5, C5, 0.5), (5.5, D5, 0.5),
            (6, C5, 1.5), (7.5, B4, 0.5), (8, C5, 0.5), (8.5, D5, 0.5),
            (9, C5, 1), (10, B4, 1), (11, A4, 1),
            (12, B4, 2), (14, G4, 2),
            (16, A4, 2), (18, B4, 1),
            (19, C5, 1.5), (20.5, B4, 0.5), (21, C5, 0.5), (21.5, D5, 0.5),
            (22, C5, 1.5), (23.5, B4, 0.5), (24, C5, 0.5), (24.5, D5, 0.5),
            (25, C5, 1), (26, B4, 1), (27, A4, 1),
            (28, A4, 4),
        ])
    )

    static let greensleeves = Song(
        name: "Greensleeves",
        composer: "Traditional English",
        bpm: 100,
        notes: assignColumns(to: [
            (0, A4, 1), (1, C5, 2), (3, D5, 1),
            (4, E5, 1.5), (5.5, F5, 0.5), (6, E5, 1),
            (7, D5, 2), (9, B4, 1),
            (10, G4, 1.5), (11.5, A4, 0.5), (12, B4, 1),
            (13, C5, 2), (15, A4, 1),
            (16, A4, 1.5), (17.5, Ab4, 0.5), (18, A4, 1),
            (19, B4, 2), (21, Ab4, 1),
            (22, E4, 2), (24, A4, 1),
            (25, C5, 2), (27, D5, 1),
            (28, E5, 1.5), (29.5, F5, 0.5), (30, E5, 1),
            (31, D5, 2), (33, B4, 1),
            (34, G4, 1.5), (35.5, A4, 0.5), (36, B4, 1),
            (37, C5, 1), (38, B4, 0.5), (38.5, A4, 0.5), (39, Ab4, 1),
            (40, E4, 1), (41, Ab4, 0.5), (41.5, A4, 0.5), (42, Ab4, 1),
            (43, A4, 3),
        ])
    )

    static let scarborough = Song(
        name: "Scarborough Fair",
        composer: "Traditional English",
        bpm: 92,
        notes: assignColumns(to: [
            (0, D4, 2), (2, D4, 1),
            (3, A4, 2), (5, A4, 1),
            (6, E4, 1.5), (7.5, F4, 0.5), (8, E4, 1),
            (9, D4, 3),
            (12, F4, 2), (14, E4, 1),
            (15, D4, 2), (17, C4, 1),
            (18, D4, 2), (20, A4, 1),
            (21, G4, 1), (22, F4, 1), (23, G4, 1),
            (24, A4, 3),
            (27, D5, 2), (29, D5, 1),
            (30, C5, 2), (32, A4, 1),
            (33, A4, 1), (34, G4, 1), (35, F4, 1),
            (36, E4, 1.5), (37.5, D4, 0.5), (38, E4, 1),
            (39, D4, 3),
        ])
    )

    // Use shorthand for readability
    private static let C3 = MIDINote.C3, D3 = MIDINote.D3, E3 = MIDINote.E3
    private static let F3 = MIDINote.F3, G3 = MIDINote.G3, A3 = MIDINote.A3
    private static let B3 = MIDINote.B3
    private static let C4 = MIDINote.C4, Cs4 = MIDINote.Cs4, D4 = MIDINote.D4
    private static let Eb4 = MIDINote.Eb4, E4 = MIDINote.E4, F4 = MIDINote.F4
    private static let Fs4 = MIDINote.Fs4, G4 = MIDINote.G4, Ab4 = MIDINote.Ab4
    private static let A4 = MIDINote.A4, Bb4 = MIDINote.Bb4, B4 = MIDINote.B4
    private static let C5 = MIDINote.C5, Cs5 = MIDINote.Cs5, D5 = MIDINote.D5
    private static let Eb5 = MIDINote.Eb5, E5 = MIDINote.E5, F5 = MIDINote.F5
    private static let Fs5 = MIDINote.Fs5, G5 = MIDINote.G5, A5 = MIDINote.A5
    private static let C6 = MIDINote.C6
}
