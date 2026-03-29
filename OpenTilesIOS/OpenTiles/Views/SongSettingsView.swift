import SwiftUI

struct SongSettingsView: View {
    let song: Song
    let onPlay: (GameSettings) -> Void
    let onBack: () -> Void

    @State private var bpmMultiplier: Double = 1.0
    @State private var loopCount: Int = 1
    @State private var mode: GameMode = .normal
    @State private var backgroundVolume: Double = 0.45

    private var effectiveBPM: Int {
        Int(song.bpm * bpmMultiplier)
    }

    private var estimatedDuration: String {
        let totalBeats = song.totalBeats * Double(loopCount == 0 ? 1 : loopCount)
        let bps = (song.bpm * bpmMultiplier) / 60.0
        let seconds = totalBeats / bps
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if loopCount == 0 { return String(localized: "Endless") }
        return String(format: "%d:%02d", mins, secs)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.blue)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            // Song info
            VStack(spacing: 8) {
                Text(song.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(song.composer)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack(spacing: 16) {
                    Label("\(song.notes.count) notes", systemImage: "music.note")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Label(estimatedDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 32)

            // Settings
            ScrollView {
                VStack(spacing: 20) {

                    // BPM
                    settingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Tempo", systemImage: "metronome")
                                    .font(.headline)
                                Spacer()
                                Text("\(effectiveBPM) BPM")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                    .contentTransition(.numericText())
                            }

                            Slider(value: $bpmMultiplier, in: 0.5...2.0, step: 0.1)
                                .tint(.blue)

                            HStack {
                                Text("Slow")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Reset") {
                                    withAnimation { bpmMultiplier = 1.0 }
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                                Spacer()
                                Text("Fast")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Background Volume (only if song has background notes)
                    if !song.backgroundNotes.isEmpty {
                        settingsCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("Background", systemImage: "speaker.wave.2")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(Int(backgroundVolume * 100))%")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                        .contentTransition(.numericText())
                                }

                                Slider(value: $backgroundVolume, in: 0.0...1.0, step: 0.05)
                                    .tint(.blue)

                                HStack {
                                    Text("Off")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("Reset") {
                                        withAnimation { backgroundVolume = 0.45 }
                                    }
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    Spacer()
                                    Text("Full")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // Loop count
                    settingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Repeat", systemImage: "repeat")
                                .font(.headline)

                            HStack(spacing: 8) {
                                ForEach([1, 2, 3, 0], id: \.self) { count in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.2)) { loopCount = count }
                                    }) {
                                        Group {
                                        if count == 0 {
                                            Text("Endless")
                                        } else {
                                            Text("\(count)x")
                                        }
                                    }
                                            .font(.subheadline.bold())
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(
                                                loopCount == count
                                                    ? Color.blue
                                                    : Color.gray.opacity(0.1)
                                            )
                                            .foregroundColor(loopCount == count ? .white : .primary)
                                            .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Game mode
                    settingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Mode", systemImage: "gamecontroller")
                                .font(.headline)

                            ForEach(GameMode.allCases) { gameMode in
                                Button(action: {
                                    withAnimation(.spring(response: 0.2)) { mode = gameMode }
                                }) {
                                    HStack {
                                        Image(systemName: gameMode.icon)
                                            .frame(width: 24)
                                            .foregroundColor(mode == gameMode ? .blue : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(gameMode.displayName)
                                                .font(.subheadline.bold())
                                                .foregroundColor(.primary)
                                            Text(gameMode.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if mode == gameMode {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(mode == gameMode ? Color.blue.opacity(0.08) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(mode == gameMode ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            // Play button
            Button(action: {
                let settings = GameSettings(
                    bpmMultiplier: bpmMultiplier,
                    loopCount: mode == .endless ? 0 : loopCount,
                    mode: mode,
                    backgroundVolume: backgroundVolume
                )
                onPlay(settings)
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Play")
                        .font(.title3.bold())
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(colors: [.blue, .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(16)
                .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}
