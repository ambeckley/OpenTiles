import SwiftUI

struct GameBoardView: View {
    @ObservedObject var gameModel: GameModel

    private let topInset: CGFloat = 60
    private let beatHeight: CGFloat = 100

    // Tracks columns where a finger is currently down — prevents multi-tap per press
    @State private var pressedColumns: Set<Int> = []

    var body: some View {
        GeometryReader { geo in
            let boardWidth = geo.size.width
            let boardHeight = geo.size.height
            let colWidth = boardWidth / CGFloat(gameModel.columnsCount)

            ZStack {
                // Canvas — single GPU draw call for all tiles
                Canvas { context, size in
                    drawBoard(context: &context, size: size)
                }
                .onChange(of: gameModel.frameCounter) { _, _ in }

                // Per-column tap zones
                HStack(spacing: 0) {
                    ForEach(0..<gameModel.columnsCount, id: \.self) { column in
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if pressedColumns.contains(column) { return }
                                        if gameModel.activeHoldColumn == column { return }
                                        pressedColumns.insert(column)
                                        handlePress(column: column, tapY: value.location.y, boardHeight: boardHeight)
                                    }
                                    .onEnded { _ in
                                        pressedColumns.remove(column)
                                        if gameModel.activeHoldColumn == column {
                                            gameModel.releaseHold()
                                            gameModel.clearHoldColumn()
                                        }
                                    }
                            )
                    }
                }

                // HUD — passes touches through to column overlays beneath
                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Score: \(gameModel.score)")
                                .font(.headline.bold())
                                .foregroundColor(.black)
                            if gameModel.combo > 1 {
                                Text("Combo x\(gameModel.combo)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.leading, 12)

                        Spacer()

                        if let rating = gameModel.lastRating {
                            Text(rating.displayName)
                                .font(.title.bold())
                                .foregroundColor(ratingColor(rating))
                                .id(gameModel.ratingTrigger)
                        }

                        Spacer()
                    }
                    .padding(.top, topInset)

                    Spacer()

                    GeometryReader { progressGeo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.gray.opacity(0.15))
                            Rectangle().fill(Color.blue)
                                .frame(width: progressGeo.size.width * gameModel.progress)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .allowsHitTesting(false)
                .zIndex(10)

                // Close button — separate so it's tappable above everything
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { gameModel.stopGame() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.gray.opacity(0.6))
                                .frame(width: 44, height: 44)
                        }
                        .padding(.trailing, 8)
                    }
                    .padding(.top, topInset)
                    Spacer()
                }
                .zIndex(15)

                if gameModel.showRedFlash {
                    Color.red.opacity(0.3)
                        .allowsHitTesting(false)
                        .zIndex(20)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Canvas Drawing

    private func drawBoard(context: inout GraphicsContext, size: CGSize) {
        let cols = gameModel.columnsCount
        let colW = size.width / CGFloat(cols)
        let hzY = size.height * (1.0 - gameModel.hitZoneFraction)
        let currentBeat = gameModel.currentBeatPosition
        let visAhead = gameModel.visibleBeatsAhead

        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))

        for i in 1..<cols {
            let x = colW * CGFloat(i)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 1)
        }

        let hzRect = CGRect(x: 4, y: hzY - beatHeight / 2 - 4, width: size.width - 8, height: beatHeight + 8)
        context.fill(Path(roundedRect: hzRect, cornerRadius: 4), with: .color(.blue.opacity(0.08)))
        context.stroke(Path(roundedRect: hzRect, cornerRadius: 4), with: .color(.blue.opacity(0.3)), lineWidth: 2)

        let topBeat = currentBeat + visAhead + (hzY / beatHeight) + 2
        let bottomBeat = currentBeat + visAhead - ((size.height - hzY) / beatHeight) - 2

        let tiles = gameModel.tiles
        let startIdx = findFirstTile(in: tiles, withBeatAtLeast: bottomBeat)

        for i in startIdx..<tiles.count {
            let tile = tiles[i]
            if tile.songNote.beatPosition > topBeat { break }

            let tileDurBeats = CGFloat(tile.songNote.duration)
            let tileH = max(beatHeight * tileDurBeats, beatHeight * 0.5)
            let beatOffset = tile.songNote.beatPosition - (currentBeat + visAhead)
            let tileCenterY = hzY - CGFloat(beatOffset) * beatHeight

            let tileRect = CGRect(
                x: colW * CGFloat(tile.songNote.column) + 1,
                y: tileCenterY - tileH / 2 + 1,
                width: colW - 2,
                height: tileH - 2
            )
            let roundedPath = Path(roundedRect: tileRect, cornerRadius: 6)

            if tile.tapped && tile.holdCompleted {
                context.opacity = 0.45
                context.fill(roundedPath, with: .color(ratingColor(tile.rating)))
                context.opacity = 1.0
                if let rating = tile.rating {
                    context.draw(
                        Text(rating.displayName).font(.system(size: 11, weight: .bold)).foregroundColor(.white),
                        at: CGPoint(x: tileRect.midX, y: tileRect.midY)
                    )
                }
            } else if tile.missed {
                context.opacity = 0.7
                context.fill(roundedPath, with: .color(.red))
                context.opacity = 1.0
            } else {
                context.fill(roundedPath, with: .color(.black))

                if tile.isLongNote && tile.isHolding && tile.holdProgress > 0 {
                    let fillH = (tileH - 2) * tile.holdProgress
                    let fillRect = CGRect(
                        x: tileRect.minX, y: tileRect.maxY - fillH,
                        width: tileRect.width, height: fillH
                    )
                    context.fill(Path(roundedRect: fillRect, cornerRadius: 6), with: .color(.cyan.opacity(0.7)))
                }

                if tile.isLongNote && !tile.tapped {
                    context.draw(
                        Text("HOLD").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.4)),
                        at: CGPoint(x: tileRect.midX, y: tileRect.midY)
                    )
                }
            }
        }
    }

    private func findFirstTile(in tiles: [GameTile], withBeatAtLeast minBeat: Double) -> Int {
        var lo = 0, hi = tiles.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if tiles[mid].songNote.beatPosition < minBeat {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return max(0, lo - 5)
    }

    // MARK: - Tap Handling

    /// Find tile at tap position — checks both column and Y visual bounds.
    private func handlePress(column: Int, tapY: CGFloat, boardHeight: CGFloat) {
        let tiles = gameModel.tiles
        let currentBeat = gameModel.currentBeatPosition
        let visAhead = gameModel.visibleBeatsAhead
        let hzY = boardHeight * (1.0 - gameModel.hitZoneFraction)
        let padding: CGFloat = 25 // extra pixels of tolerance around tile edges

        var bestIndex: Int?
        var bestDist: CGFloat = .infinity

        // Convert tapY to approximate beat for binary search start
        let approxBeat = -Double((tapY - hzY) / beatHeight) + currentBeat + visAhead
        let searchStart = findFirstTile(in: tiles, withBeatAtLeast: approxBeat - 8)

        for i in searchStart..<tiles.count {
            let tile = tiles[i]
            // Stop if tiles are way past the tap area
            if tile.songNote.beatPosition > approxBeat + 8 { break }
            guard tile.songNote.column == column else { continue }
            guard !tile.tapped && !tile.missed else { continue }

            // Calculate tile's visual Y bounds (must match Canvas drawing exactly)
            let tileDurBeats = CGFloat(tile.songNote.duration)
            let tileH = max(beatHeight * tileDurBeats, beatHeight * 0.5)
            let beatOffset = tile.songNote.beatPosition - (currentBeat + visAhead)
            let tileCenterY = hzY - CGFloat(beatOffset) * beatHeight
            let tileTop = tileCenterY - tileH / 2 - padding
            let tileBot = tileCenterY + tileH / 2 + padding

            // Check if tap Y is within tile visual bounds
            if tapY >= tileTop && tapY <= tileBot {
                let dist = abs(tapY - tileCenterY)
                if dist < bestDist {
                    bestDist = dist
                    bestIndex = i
                }
            }
        }

        if let idx = bestIndex {
            let tile = tiles[idx]
            if tile.isLongNote {
                if gameModel.activeHoldTileID != tile.id {
                    gameModel.startHold(tile.id)
                }
            } else {
                gameModel.tapTile(tile.id)
            }
        } else {
            // Tapped empty space in this column — wrong tap penalty
            gameModel.tapBackground()
        }
    }

    private func ratingColor(_ rating: TapRating?) -> Color {
        switch rating {
        case .perfect: return .green
        case .great: return .blue
        case .good: return .orange
        case .none: return .gray
        }
    }
}

