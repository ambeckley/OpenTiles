import SwiftUI
import Combine

enum GameState: Equatable {
    case menu
    case playing
    case gameOver(won: Bool)
}

enum TapRating: String {
    case perfect
    case great
    case good

    var displayName: String {
        switch self {
        case .perfect: return String(localized: "Perfect!")
        case .great: return String(localized: "Great")
        case .good: return String(localized: "Good")
        }
    }
}

struct GameTile: Identifiable {
    let id = UUID()
    let noteIndex: Int
    let songNote: SongNote
    var tapped: Bool = false
    var missed: Bool = false
    var rating: TapRating?
    var tapTime: Date?
    var isHolding: Bool = false
    var holdProgress: Double = 0
    var holdCompleted: Bool = false

    var isLongNote: Bool {
        songNote.midiNotes.count >= 3
    }

    var isResolved: Bool {
        missed || (tapped && (!isLongNote || holdCompleted))
    }
}

class GameModel: ObservableObject {
    // Only publish what the view actually needs to re-render
    @Published var gameState: GameState = .menu
    @Published var score: Int = 0
    @Published var combo: Int = 0
    @Published var maxCombo: Int = 0
    @Published var lastRating: TapRating?
    @Published var ratingTrigger: UUID = UUID()
    @Published var perfectCount: Int = 0
    @Published var greatCount: Int = 0
    @Published var goodCount: Int = 0
    @Published var progress: Double = 0
    @Published var showRedFlash: Bool = false
    @Published var missCount: Int = 0
    @Published var loopNumber: Int = 0

    // These update 60fps — NOT @Published to avoid triggering SwiftUI re-renders
    // The Canvas reads them directly
    var currentBeatPosition: Double = 0
    var tiles: [GameTile] = []
    var activeHoldTileID: UUID?
    var activeHoldColumn: Int = -1

    // Trigger a Canvas redraw without full SwiftUI re-layout
    @Published var frameCounter: UInt64 = 0

    let wrongNotePenalty: Int = 50

    var song: Song?
    var settings: GameSettings = GameSettings()
    let toneGenerator = ToneGenerator()
    let backgroundToneGenerator = ToneGenerator(volume: 0.45)

    private var gameTimer: AnyCancellable?
    private var bgNoteCursor: Int = 0  // tracks which background note to play next
    private var gameStartTime: TimeInterval = 0
    private var holdStartTime: TimeInterval?
    private var gameEnding: Bool = false
    private var baseSong: Song?

    // Cursor: index of the first tile that hasn't scrolled past yet
    // Avoids scanning all tiles every frame
    private(set) var scanCursor: Int = 0
    private var resolvedCount: Int = 0

    var scanCursorValue: Int { scanCursor }

    let columnsCount = 4
    let visibleBeatsAhead: Double = 6.0
    let leadInBeats: Double = 8.0
    let hitZoneFraction: CGFloat = 0.2
    let tapWindowBeats: Double = 2.5
    let missWindowBeats: Double = 3.0
    static let holdThreshold: Double = 1.0

    var beatsPerSecond: Double {
        guard let song = song else { return 2.0 }
        return (song.bpm * settings.bpmMultiplier) / 60.0
    }

    var isPracticeMode: Bool { settings.mode == .practice }
    var isEndlessMode: Bool { settings.mode == .endless }

    func startGame(song: Song, settings: GameSettings = GameSettings()) {
        self.baseSong = song
        self.settings = settings
        backgroundToneGenerator.setVolume(settings.backgroundVolume)

        if settings.mode != .endless && settings.loopCount > 1 {
            self.song = song.looped(times: settings.loopCount)
        } else {
            self.song = song
        }

        tiles = []
        score = 0
        combo = 0
        maxCombo = 0
        perfectCount = 0
        greatCount = 0
        goodCount = 0
        progress = 0
        lastRating = nil
        showRedFlash = false
        activeHoldTileID = nil
        activeHoldColumn = -1
        holdStartTime = nil
        missCount = 0
        gameEnding = false
        loopNumber = 0
        scanCursor = 0
        resolvedCount = 0
        bgNoteCursor = 0
        currentBeatPosition = -(visibleBeatsAhead + leadInBeats)

        for (index, note) in self.song!.notes.enumerated() {
            tiles.append(GameTile(noteIndex: index, songNote: note))
        }

        gameStartTime = CACurrentMediaTime()
        gameState = .playing

        gameTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.gameLoop()
            }
    }

    private func gameLoop() {
        guard let song = song, case .playing = gameState else { return }

        let elapsed = CACurrentMediaTime() - gameStartTime
        currentBeatPosition = (elapsed * beatsPerSecond) - visibleBeatsAhead - leadInBeats

        let hitBeat = currentBeatPosition + visibleBeatsAhead

        // Update hold progress
        if let holdID = activeHoldTileID,
           let index = tiles.firstIndex(where: { $0.id == holdID }),
           let holdStart = holdStartTime {
            let holdElapsed = CACurrentMediaTime() - holdStart
            let requiredDuration = tiles[index].songNote.duration / beatsPerSecond
            let prog = min(holdElapsed / requiredDuration, 1.0)
            tiles[index].holdProgress = prog

            if prog >= 0.85 {
                completeHold(at: index)
            }
        }

        // Check for missed tiles — only scan from cursor forward, stop when tiles are ahead
        if !isPracticeMode {
            var i = scanCursor
            while i < tiles.count {
                let tileBeat = tiles[i].songNote.beatPosition
                // If this tile is still ahead of the miss window, all subsequent ones are too
                if hitBeat - tileBeat <= missWindowBeats { break }

                if !tiles[i].tapped && !tiles[i].missed {
                    tiles[i].missed = true
                    resolvedCount += 1
                    penalize()
                }
                i += 1
            }
            // Advance cursor past fully resolved tiles
            while scanCursor < tiles.count && tiles[scanCursor].isResolved {
                scanCursor += 1
            }
        }

        // Play background notes as they reach the hit zone
        playBackgroundNotes(hitBeat: hitBeat)

        // Update progress (use counter instead of filter)
        progress = tiles.isEmpty ? 0 : Double(resolvedCount) / Double(tiles.count)

        // Check win
        if !gameEnding && resolvedCount >= tiles.count {
            if isEndlessMode {
                appendNextLoop()
            } else {
                endGame(won: true)
            }
        }

        // Bump frame counter to trigger Canvas redraw
        frameCounter &+= 1
    }

    private func appendNextLoop() {
        guard let baseSong = baseSong else { return }
        loopNumber += 1
        let totalBeats = baseSong.totalBeats
        let offset = totalBeats * Double(loopNumber)

        let newNotes = SongLibrary.assignColumnsChords(
            to: baseSong.notes.map { note in
                (beat: note.beatPosition + offset, midiNotes: note.midiNotes, dur: note.duration)
            }
        )

        for (index, note) in newNotes.enumerated() {
            tiles.append(GameTile(noteIndex: index, songNote: note))
        }
    }

    // MARK: - Tap handling

    func tapTile(_ tileID: UUID) {
        guard case .playing = gameState else { return }
        guard let index = tiles.firstIndex(where: { $0.id == tileID }) else { return }
        guard !tiles[index].tapped && !tiles[index].missed else { return }
        if tiles[index].isLongNote { return }
        performTap(at: index)
    }

    func startHold(_ tileID: UUID) {
        guard case .playing = gameState else { return }
        guard let index = tiles.firstIndex(where: { $0.id == tileID }) else { return }
        guard !tiles[index].tapped && !tiles[index].missed else { return }
        guard tiles[index].isLongNote else {
            performTap(at: index)
            return
        }

        tiles[index].tapped = true
        tiles[index].tapTime = Date()
        tiles[index].isHolding = true
        activeHoldTileID = tileID
        activeHoldColumn = tiles[index].songNote.column
        holdStartTime = CACurrentMediaTime()
        playTileAudio(tiles[index].songNote)
    }

    /// Called by the view when finger lifts from a hold column
    func clearHoldColumn() {
        activeHoldColumn = -1
    }

    func releaseHold() {
        guard let holdID = activeHoldTileID,
              let index = tiles.firstIndex(where: { $0.id == holdID }) else {
            activeHoldTileID = nil
            holdStartTime = nil
            return
        }

        if tiles[index].holdProgress >= 0.85 {
            completeHold(at: index)
        } else {
            // Released early — just cut the note off, small penalty, no red flash
            tiles[index].isHolding = false
            tiles[index].holdCompleted = true
            resolvedCount += 1
            activeHoldTileID = nil
            holdStartTime = nil
            toneGenerator.stop()
            if !isPracticeMode {
                combo = 0
                missCount += 1
                score = max(0, score - wrongNotePenalty)
            }
        }
    }

    private func completeHold(at index: Int) {
        tiles[index].isHolding = false
        tiles[index].holdCompleted = true
        tiles[index].holdProgress = 1.0
        resolvedCount += 1
        activeHoldTileID = nil
        holdStartTime = nil

        let rating: TapRating
        if tiles[index].holdProgress >= 0.95 {
            rating = .perfect; perfectCount += 1; score += 100
        } else if tiles[index].holdProgress >= 0.9 {
            rating = .great; greatCount += 1; score += 75
        } else {
            rating = .good; goodCount += 1; score += 50
        }

        tiles[index].rating = rating
        lastRating = rating
        ratingTrigger = UUID()
        combo += 1
        maxCombo = max(maxCombo, combo)
    }

    private func performTap(at index: Int) {
        let hitBeat = currentBeatPosition + visibleBeatsAhead
        let tileBeat = tiles[index].songNote.beatPosition
        let beatDistance = abs(hitBeat - tileBeat)

        tiles[index].tapped = true
        tiles[index].tapTime = Date()
        tiles[index].holdCompleted = true
        resolvedCount += 1

        let secondsOff = beatDistance / beatsPerSecond
        let rating: TapRating
        if secondsOff < 0.08 {
            rating = .perfect; perfectCount += 1; score += 100
        } else if secondsOff < 0.2 {
            rating = .great; greatCount += 1; score += 75
        } else {
            rating = .good; goodCount += 1; score += 50
        }

        tiles[index].rating = rating
        lastRating = rating
        ratingTrigger = UUID()
        combo += 1
        maxCombo = max(maxCombo, combo)
        playTileAudio(tiles[index].songNote)
    }

    private func playTileAudio(_ note: SongNote) {
        let bps = beatsPerSecond
        let primaryDuration = note.duration / bps
        toneGenerator.playNotes(midiNotes: note.midiNotes, duration: primaryDuration)
        for arp in note.arpeggio {
            toneGenerator.playNotesDelayed(
                midiNotes: arp.midiNotes,
                delaySeconds: arp.delayBeats / bps,
                duration: arp.duration / bps
            )
        }
    }

    /// Auto-play background accompaniment notes as they pass the hit zone
    private func playBackgroundNotes(hitBeat: Double) {
        guard let song = song else { return }
        let bgNotes = song.backgroundNotes
        let bps = beatsPerSecond

        while bgNoteCursor < bgNotes.count {
            let bgNote = bgNotes[bgNoteCursor]
            if bgNote.beatPosition > hitBeat {
                break // not yet
            }
            // Play this background note at lower volume via the background generator
            let dur = bgNote.duration / bps
            backgroundToneGenerator.playNotes(midiNotes: bgNote.midiNotes, duration: dur)
            bgNoteCursor += 1
        }
    }

    func tapBackground() {
        guard case .playing = gameState else { return }
        if !isPracticeMode { penalize() }
    }

    private func penalize() {
        combo = 0
        missCount += 1
        score = max(0, score - wrongNotePenalty)
        triggerRedFlash()
        toneGenerator.playWrongNote()
    }

    private func triggerRedFlash() {
        showRedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showRedFlash = false
        }
    }

    private func endGame(won: Bool) {
        guard !gameEnding else { return }
        gameEnding = true
        activeHoldTileID = nil
        holdStartTime = nil
        let delay: Double = won ? 0.8 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.gameTimer?.cancel()
            self?.gameTimer = nil
            withAnimation(.easeInOut(duration: 0.4)) {
                self?.gameState = .gameOver(won: won)
            }
        }
    }

    func stopGame() {
        gameTimer?.cancel()
        gameTimer = nil
        toneGenerator.stop()
        backgroundToneGenerator.stop()
        activeHoldTileID = nil
        activeHoldColumn = -1
        holdStartTime = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            gameState = .menu
        }
    }

    var starRating: Int {
        let total = perfectCount + greatCount + goodCount
        guard total > 0 else { return 0 }
        let accuracy = Double(perfectCount * 100 + greatCount * 75 + goodCount * 50) / Double(total * 100)
        if accuracy >= 0.9 { return 3 }
        if accuracy >= 0.7 { return 2 }
        if accuracy >= 0.5 { return 1 }
        return 0
    }
}
