import SwiftUI

struct TileView: View {
    let tile: GameTile
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main tile body — simple rectangle, no shadow for performance
            RoundedRectangle(cornerRadius: 6)
                .fill(tileColor)
                .frame(width: width - 2, height: height - 2)

            // Hold progress fill (fills from bottom to top)
            if tile.isLongNote && tile.isHolding {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.cyan.opacity(0.7))
                    .frame(width: width - 2, height: (height - 2) * tile.holdProgress)
            }

            // Hold completed fill
            if tile.isLongNote && tile.holdCompleted {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ratingColor.opacity(0.5))
                    .frame(width: width - 2, height: height - 2)
            }

            // HOLD label on untapped long notes
            if tile.isLongNote && !tile.tapped && !tile.missed {
                Text("HOLD")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: width - 2, height: height - 2)
            }

            // Rating text on tapped tiles
            if tile.tapped && tile.holdCompleted, let rating = tile.rating {
                Text(rating.displayName)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .frame(width: width - 2, height: height - 2)
            }
        }
        .opacity(tile.tapped && tile.holdCompleted ? 0.5 : 1.0)
        .drawingGroup() // Flatten to single GPU layer for performance
    }

    private var tileColor: Color {
        if tile.tapped && !tile.isLongNote {
            return ratingColor.opacity(0.6)
        } else if tile.missed {
            return .red.opacity(0.8)
        } else if tile.isLongNote && !tile.tapped {
            return Color(white: 0.12)
        } else {
            return .black
        }
    }

    private var ratingColor: Color {
        switch tile.rating {
        case .perfect: return .green
        case .great: return .blue
        case .good: return .orange
        case .none: return .gray
        }
    }
}
