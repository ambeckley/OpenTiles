//
//  ContentView.swift
//  pianotiles
//
//  Created by Aaron Beckley on 3/21/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var gameModel = GameModel()
    @State private var lastSong: Song?
    @State private var customSongs: [Song] = ContentView.loadCustomSongs()
    @State private var selectedSong: Song?
    @AppStorage("favoriteSongs") private var favoriteSongsData: String = ""

    private static let customSongsURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("customSongs.json")
    }()

    private static func loadCustomSongs() -> [Song] {
        guard let data = try? Data(contentsOf: customSongsURL),
              let songs = try? JSONDecoder().decode([Song].self, from: data) else {
            return []
        }
        return songs
    }

    private func saveCustomSongs() {
        if let data = try? JSONEncoder().encode(customSongs) {
            try? data.write(to: Self.customSongsURL)
        }
    }

    private var favoriteSongNames: Set<String> {
        Set(favoriteSongsData.split(separator: "\n").map(String.init))
    }

    private var allSongs: [Song] {
        SongLibrary.songs + customSongs
    }

    var body: some View {
        ZStack {
            if let song = selectedSong, case .menu = gameModel.gameState {
                // Song settings screen
                SongSettingsView(
                    song: song,
                    onPlay: { settings in
                        lastSong = song
                        selectedSong = nil
                        withAnimation(.easeInOut(duration: 0.3)) {
                            gameModel.startGame(song: song, settings: settings)
                        }
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedSong = nil
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                switch gameModel.gameState {
                case .menu:
                    MenuView(
                        songs: allSongs,
                        builtInCount: SongLibrary.songs.count,
                        favorites: favoriteSongNames,
                        onSelectSong: { song in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedSong = song
                            }
                        },
                        onImportMIDI: { song in
                            customSongs.append(song)
                            saveCustomSongs()
                        },
                        onDeleteSong: { song in
                            customSongs.removeAll { $0.id == song.id }
                            saveCustomSongs()
                        },
                        onToggleFavorite: { song in
                            var names = favoriteSongNames
                            if names.contains(song.name) {
                                names.remove(song.name)
                            } else {
                                names.insert(song.name)
                            }
                            favoriteSongsData = names.joined(separator: "\n")
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                case .playing:
                    GameBoardView(gameModel: gameModel)
                        .transition(.opacity)

                case .gameOver:
                    GameOverView(
                        won: gameOverWon,
                        score: gameModel.score,
                        maxCombo: gameModel.maxCombo,
                        perfectCount: gameModel.perfectCount,
                        greatCount: gameModel.greatCount,
                        goodCount: gameModel.goodCount,
                        missCount: gameModel.missCount,
                        starRating: gameModel.starRating,
                        songName: lastSong?.name ?? "",
                        onRestart: {
                            if let song = lastSong {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    gameModel.startGame(song: song, settings: gameModel.settings)
                                }
                            }
                        },
                        onMenu: {
                            gameModel.stopGame()
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: gameModel.gameState)
        .animation(.easeInOut(duration: 0.3), value: selectedSong?.id)
    }

    private var gameOverWon: Bool {
        if case .gameOver(let won) = gameModel.gameState { return won }
        return false
    }
}

#Preview {
    ContentView()
}
