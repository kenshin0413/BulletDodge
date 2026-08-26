import SwiftUI
import UIKit

struct RankingShareContext: Equatable {
    let playerName: String
    let profileIcon: ProfileIcon
    let worldRank: Int?
    let season: RankingSeason
    let isPersonalBest: Bool
}

struct RankingSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
    let message: String
}

@MainActor
enum RankingShareRenderer {
    static func render(result: GameResult, context: RankingShareContext) -> UIImage? {
        let renderer = ImageRenderer(
            content: RankingShareCard(result: result, context: context)
        )
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1_080, height: 1_080)
        return renderer.uiImage
    }
}

struct RankingShareCard: View {
    let result: GameResult
    let context: RankingShareContext

    private var performanceRank: PerformanceRank {
        PerformanceRank(survivalTime: result.survivalTime)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.025, blue: 0.026),
                    Color(red: 0.13, green: 0.025, blue: 0.035),
                    Color(red: 0.025, green: 0.02, blue: 0.022)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            decorativeSpikes

            VStack(spacing: 0) {
                brandHeader
                Spacer(minLength: 24)
                recordPanel
                Spacer(minLength: 30)
                promotionalFooter
            }
            .padding(58)
        }
        .frame(width: 1_080, height: 1_080)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    private var brandHeader: some View {
        HStack(spacing: 24) {
            ShareAppIcon()
                .frame(width: 118, height: 118)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("app.display_name"))
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.82)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(context.season.localizedLabel.uppercased())
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(Color(red: 1.0, green: 0.29, blue: 0.36))
            }

            Spacer()

            if context.isPersonalBest {
                Text(L10n.text("ranking.share.new_record"))
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(Color(red: 0.90, green: 0.08, blue: 0.17), in: Capsule())
            }
        }
    }

    private var recordPanel: some View {
        VStack(spacing: 26) {
            RankingIconView(icon: context.profileIcon, size: 128)
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 3))
                .shadow(color: .red.opacity(0.55), radius: 24)

            Text(context.playerName)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.60)

            HStack(spacing: 24) {
                shareStat(
                    label: L10n.text("ranking.share.world_rank"),
                    value: context.worldRank.map { "#\($0)" } ?? "—",
                    color: Color(red: 1.0, green: 0.73, blue: 0.18)
                )
                shareStat(
                    label: L10n.text("ranking.share.survival"),
                    value: L10n.format("format.seconds_short", result.survivalTime),
                    color: Color(red: 0.12, green: 0.84, blue: 0.94)
                )
                shareStat(
                    label: L10n.text("stats.rank"),
                    value: performanceRank.rawValue,
                    color: Color(red: 1.0, green: 0.30, blue: 0.42)
                )
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 38)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.red.opacity(0.9), .white.opacity(0.16), .red.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        }
        .shadow(color: .black.opacity(0.65), radius: 28, y: 18)
    }

    private func shareStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(value)
                .font(.system(size: 58, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .frame(maxWidth: .infinity, minHeight: 122)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
    }

    private var promotionalFooter: some View {
        VStack(spacing: 15) {
            Text(L10n.text("ranking.share.challenge"))
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            HStack(spacing: 11) {
                Image(systemName: "apple.logo")
                Text(L10n.text("ranking.share.download"))
            }
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.76))
        }
    }

    private var decorativeSpikes: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                Image(systemName: "triangle.fill")
                    .font(.system(size: index.isMultiple(of: 2) ? 110 : 74, weight: .black))
                    .foregroundStyle(Color.red.opacity(index.isMultiple(of: 3) ? 0.13 : 0.07))
                    .rotationEffect(.degrees(Double(index) * 47))
                    .offset(
                        x: cos(Double(index) * .pi / 6) * 480,
                        y: sin(Double(index) * .pi / 6) * 470
                    )
            }
            Circle()
                .stroke(Color.red.opacity(0.12), lineWidth: 36)
                .frame(width: 870, height: 870)
            Circle()
                .stroke(Color.red.opacity(0.08), lineWidth: 3)
                .frame(width: 760, height: 760)
        }
    }
}

private struct ShareAppIcon: View {
    var body: some View {
        Group {
            if let image = Self.appIcon {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("season_champion")
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.34), lineWidth: 2))
        .shadow(color: .red.opacity(0.50), radius: 18, y: 8)
    }

    private static let appIcon: UIImage? = {
        if let direct = UIImage(named: "AppIcon") { return direct }
        let dictionaries = [
            Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            Bundle.main.infoDictionary?["CFBundleIcons~ipad"] as? [String: Any]
        ]
        for dictionary in dictionaries.compactMap({ $0 }) {
            guard let primary = dictionary["CFBundlePrimaryIcon"] as? [String: Any],
                  let files = primary["CFBundleIconFiles"] as? [String],
                  let name = files.last,
                  let image = UIImage(named: name) else { continue }
            return image
        }
        return nil
    }()
}

struct RankingActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
