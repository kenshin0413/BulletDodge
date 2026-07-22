import SwiftUI

struct HomeView: View {
    let bestSurvivalTime: TimeInterval
    let bestDodgedCount: Int
    let onStart: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.94, green: 0.88, blue: 0.74), Color(red: 0.84, green: 0.76, blue: 0.59)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Group {
                    if isLandscape {
                        HStack(spacing: 24) {
                            titleBlock(alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(spacing: 16) {
                                RecordCard(title: "最高生存時間", value: String(format: "%.1f 秒", bestSurvivalTime))
                                RecordCard(title: "最高回避数", value: "\(bestDodgedCount) 発")
                                startButton
                            }
                            .frame(maxWidth: 420)
                        }
                    } else {
                        VStack(spacing: 28) {
                            Spacer()
                            titleBlock(alignment: .center)
                            VStack(spacing: 16) {
                                RecordCard(title: "最高生存時間", value: String(format: "%.1f 秒", bestSurvivalTime))
                                RecordCard(title: "最高回避数", value: "\(bestDodgedCount) 発")
                            }
                            startButton
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, isLandscape ? 40 : 24)
                .padding(.vertical, isLandscape ? 24 : 32)
            }
        }
    }

    private func titleBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 12) {
            Text("Bullet Dodge")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.17, blue: 0.20))

            Text("Top-down dodge training")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.black.opacity(0.55))
        }
    }

    private var startButton: some View {
        Button(action: onStart) {
            Text("練習開始")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(Color(red: 0.17, green: 0.44, blue: 0.90))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        }
    }
}

private struct RecordCard: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.68))

            Spacer()

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.17, blue: 0.20))
        }
        .padding(20)
        .background(.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    HomeView(bestSurvivalTime: 41.7, bestDodgedCount: 93, onStart: {})
}
