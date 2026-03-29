import SwiftUI
import UniformTypeIdentifiers

struct MenuView: View {
    let songs: [Song]
    let builtInCount: Int
    let favorites: Set<String>
    let onSelectSong: (Song) -> Void
    let onImportMIDI: (Song) -> Void
    let onDeleteSong: (Song) -> Void
    let onToggleFavorite: (Song) -> Void

    @State private var headerVisible = false
    @State private var cardsVisible = false
    @State private var showFileImporter = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var searchText: String = ""
    @State private var builtInExpanded = true
    @State private var importedExpanded = true
    @State private var importedCount = 0

    private var builtInSongs: [Song] {
        Array(songs.prefix(builtInCount))
    }

    private var importedSongs: [Song] {
        Array(songs.dropFirst(builtInCount))
    }

    private func filterAndSort(_ list: [Song]) -> [Song] {
        let filtered: [Song]
        if searchText.isEmpty {
            filtered = list
        } else {
            let query = searchText.lowercased()
            filtered = list.filter {
                $0.name.lowercased().contains(query) ||
                $0.composer.lowercased().contains(query)
            }
        }
        return filtered.sorted { a, b in
            let aFav = favorites.contains(a.name)
            let bFav = favorites.contains(b.name)
            if aFav != bFav { return aFav }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "pianokeys")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(colors: [.black, .gray], startPoint: .top, endPoint: .bottom)
                    )
                    .scaleEffect(headerVisible ? 1.0 : 0.5)
                    .opacity(headerVisible ? 1.0 : 0.0)

                Text("OpenTiles")
                    .font(.largeTitle.bold())
                    .offset(y: headerVisible ? 0 : 20)
                    .opacity(headerVisible ? 1.0 : 0.0)

                Text("Tap the black tiles to play the song")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .offset(y: headerVisible ? 0 : 10)
                    .opacity(headerVisible ? 1.0 : 0.0)
            }
            .padding(.top, 60)
            .padding(.bottom, 20)

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search songs or composers...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Song list
            ScrollView {
                VStack(spacing: 16) {

                    // Import MIDI button
                    Button(action: { showFileImporter = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import MIDI Files")
                                    .font(.headline)
                                Text("Single or multiple files")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "doc.badge.plus")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.blue)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                        )
                    }

                    // Built-in songs section
                    songSection(
                        title: "Built-in Songs",
                        icon: "music.note.list",
                        songs: filterAndSort(builtInSongs),
                        isExpanded: $builtInExpanded,
                        isImported: false
                    )

                    // Imported songs section
                    if !importedSongs.isEmpty {
                        songSection(
                            title: "Imported Songs",
                            icon: "square.and.arrow.down",
                            songs: filterAndSort(importedSongs),
                            isExpanded: $importedExpanded,
                            isImported: true
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            Spacer()
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                headerVisible = true
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                cardsVisible = true
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.midi, UTType(filenameExtension: "mid") ?? .midi],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                var errors: [String] = []
                for url in urls {
                    do {
                        let song = try MIDIImporter.importMIDI(from: url)
                        onImportMIDI(song)
                        importedCount += 1
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                if !errors.isEmpty {
                    importError = errors.joined(separator: "\n")
                    showImportError = true
                }
            case .failure(let error):
                importError = error.localizedDescription
                showImportError = true
            }
        }
        .alert(String(localized: "Import Error"), isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func songSection(
        title: String,
        icon: String,
        songs: [Song],
        isExpanded: Binding<Bool>,
        isImported: Bool
    ) -> some View {
        VStack(spacing: 8) {
            // Section header — tap to collapse/expand
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.wrappedValue.toggle()
                }
            }) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    Text("(\(songs.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            if isExpanded.wrappedValue {
                ForEach(songs) { song in
                    let isFavorite = favorites.contains(song.name)
                    SongCard(song: song, isImported: isImported, isFavorite: isFavorite, onTap: {
                        onSelectSong(song)
                    }, onDelete: isImported ? {
                        withAnimation(.spring(response: 0.3)) {
                            onDeleteSong(song)
                        }
                    } : nil, onToggleFavorite: {
                        withAnimation(.spring(response: 0.3)) {
                            onToggleFavorite(song)
                        }
                    })
                }
            }
        }
    }
}

struct SongCard: View {
    let song: Song
    let isImported: Bool
    let isFavorite: Bool
    let onTap: () -> Void
    let onDelete: (() -> Void)?
    let onToggleFavorite: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(song.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if isImported {
                            Text("IMPORTED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.6))
                                .cornerRadius(4)
                        }
                    }
                    Text(song.composer)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Text("\(song.notes.count) notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if song.notes.contains(where: { $0.midiNotes.count >= 3 }) {
                            Label("Hold notes", systemImage: "hand.tap.fill")
                                .font(.caption2)
                                .foregroundColor(.blue.opacity(0.7))
                        }
                    }
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(Int(song.bpm))")
                        .font(.title3.bold())
                        .foregroundColor(.blue)
                    Text("BPM")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 8) {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.body)
                            .foregroundColor(isFavorite ? .red : .gray.opacity(0.4))
                    }
                    .buttonStyle(.plain)

                    if let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: .black.opacity(isPressed ? 0.02 : 0.06), radius: isPressed ? 2 : 4, y: isPressed ? 1 : 2)
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}
