import SwiftUI

struct GameOverView: View {
    let won: Bool
    let score: Int
    let maxCombo: Int
    let perfectCount: Int
    let greatCount: Int
    let goodCount: Int
    let missCount: Int
    let starRating: Int
    let songName: String
    let onRestart: () -> Void
    let onMenu: () -> Void

    @State private var iconVisible = false
    @State private var contentVisible = false
    @State private var starsVisible = false
    @State private var scoreVisible = false
    @State private var statsVisible = false
    @State private var buttonsVisible = false
    @State private var displayedScore = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Result icon
            Image(systemName: won ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    won
                        ? LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .scaleEffect(iconVisible ? 1.0 : 0.0)
                .rotationEffect(.degrees(iconVisible ? 0 : -180))
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: iconVisible)

            Text(won ? "Song Complete!" : "Game Over")
                .font(.largeTitle.bold())
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 20)

            Text(songName)
                .font(.title3)
                .foregroundColor(.secondary)
                .opacity(contentVisible ? 1 : 0)

            // Stars
            if won {
                HStack(spacing: 12) {
                    ForEach(1...3, id: \.self) { star in
                        Image(systemName: star <= starRating ? "star.fill" : "star")
                            .font(.largeTitle)
                            .foregroundColor(.yellow)
                            .shadow(color: star <= starRating ? .yellow.opacity(0.5) : .clear, radius: 6)
                            .scaleEffect(starsVisible ? 1.0 : 0.0)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.5)
                                    .delay(Double(star) * 0.15),
                                value: starsVisible
                            )
                    }
                }
            }

            // Score with count-up animation
            VStack(spacing: 8) {
                Text("\(displayedScore)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
                    )
                    .contentTransition(.numericText())
                    .scaleEffect(scoreVisible ? 1.0 : 0.5)
                    .opacity(scoreVisible ? 1 : 0)

                Text("Score")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .opacity(scoreVisible ? 1 : 0)
            }

            // Stats
            HStack(spacing: 20) {
                StatItem(label: "Perfect", count: perfectCount, color: .green)
                    .opacity(statsVisible ? 1 : 0)
                    .offset(x: statsVisible ? 0 : -30)
                StatItem(label: "Great", count: greatCount, color: .blue)
                    .opacity(statsVisible ? 1 : 0)
                    .scaleEffect(statsVisible ? 1.0 : 0.5)
                StatItem(label: "Good", count: goodCount, color: .orange)
                    .opacity(statsVisible ? 1 : 0)
                    .offset(x: statsVisible ? 0 : 30)
                if missCount > 0 {
                    StatItem(label: "Miss", count: missCount, color: .red)
                        .opacity(statsVisible ? 1 : 0)
                        .offset(x: statsVisible ? 0 : 30)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: statsVisible)

            if maxCombo > 1 {
                Text("Max Combo: \(maxCombo)")
                    .font(.headline)
                    .foregroundColor(.orange)
                    .opacity(statsVisible ? 1 : 0)
            }

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button(action: onRestart) {
                    Label("Play Again", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [.blue, .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(14)
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                }

                Button(action: onMenu) {
                    Label("Song List", systemImage: "music.note.list")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
            .offset(y: buttonsVisible ? 0 : 50)
            .opacity(buttonsVisible ? 1 : 0)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear {
            // Staggered entrance
            withAnimation { iconVisible = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) { contentVisible = true }
            withAnimation(.easeOut.delay(0.4)) { starsVisible = true }
            withAnimation(.easeOut.delay(0.5)) { scoreVisible = true }
            withAnimation(.easeOut.delay(0.7)) { statsVisible = true }
            withAnimation(.spring(response: 0.5).delay(0.9)) { buttonsVisible = true }

            // Score count-up
            animateScore()
        }
    }

    private func animateScore() {
        let steps = 30
        let stepDuration = 0.8 / Double(steps)
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + stepDuration * Double(i)) {
                withAnimation(.snappy(duration: 0.05)) {
                    displayedScore = Int(Double(score) * Double(i) / Double(steps))
                }
            }
        }
    }
}

struct StatItem: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundColor(color)
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
