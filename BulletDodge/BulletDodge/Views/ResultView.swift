import SwiftUI

struct ResultView: View {
    let result: GameResult
    let bestSurvivalTime: TimeInterval
    let bestDodgedCount: Int
    let onRetry: () -> Void
    let onHome: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.11, green: 0.14, blue: 0.19), Color(red: 0.19, green: 0.23, blue: 0.29)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: isLandscape ? 18 : 22) {
                        Text("RESULT")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        VStack(spacing: 14) {
                            resultRows
                            actionButtons
                        }
                        .frame(maxWidth: 460)
                        .padding(isLandscape ? 22 : 20)
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, isLandscape ? 32 : 24)
                    .padding(.top, isLandscape ? 18 : 32)
                    .padding(.bottom, isLandscape ? 18 : 32)
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
    }

    private var resultRows: some View {
        VStack(spacing: 14) {
            ResultRow(title: "生存時間", value: String(format: "%.1f 秒", result.survivalTime))
            ResultRow(title: "回避数", value: "\(result.dodgedCount) 発")
            ResultRow(title: "被弾回数", value: "\(result.hitCount) 回")
            ResultRow(title: "最高生存時間", value: String(format: "%.1f 秒", bestSurvivalTime))
            ResultRow(title: "最高回避数", value: "\(bestDodgedCount) 発")
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onRetry) {
                Text("もう一度")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color(red: 0.17, green: 0.44, blue: 0.90))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Button(action: onHome) {
                Text("ホームへ戻る")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

private struct ResultRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
        .font(.system(size: 18, weight: .semibold, design: .rounded))
        .padding(18)
        .background(.white.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    ResultView(
        result: GameResult(survivalTime: 18.4, dodgedCount: 22, hitCount: 5),
        bestSurvivalTime: 41.7,
        bestDodgedCount: 93,
        onRetry: {},
        onHome: {}
    )
}
