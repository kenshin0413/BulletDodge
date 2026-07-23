import SwiftUI

enum GameTheme {
    static let midnight = Color(red: 0.055, green: 0.035, blue: 0.105)
    static let plum = Color(red: 0.16, green: 0.07, blue: 0.24)
    static let panel = Color(red: 0.10, green: 0.065, blue: 0.16)
    static let cyan = Color(red: 0.20, green: 0.82, blue: 0.92)
    static let coral = Color(red: 1.00, green: 0.29, blue: 0.35)
    static let gold = Color(red: 1.00, green: 0.73, blue: 0.20)
    static let mint = Color(red: 0.30, green: 0.91, blue: 0.62)
    static let softText = Color.white.opacity(0.68)
}

struct ArenaShellBackground: View {
    let glowColor: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("arena_floor_v1")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .saturation(0.72)
                    .contrast(1.08)

                LinearGradient(
                    colors: [
                        GameTheme.midnight.opacity(0.72),
                        GameTheme.plum.opacity(0.82),
                        GameTheme.midnight.opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [glowColor.opacity(0.24), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.72
                )

                LinearGradient(
                    colors: [.clear, .black.opacity(0.36)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct GameChromePanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(GameTheme.panel.opacity(0.88))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.22), GameTheme.cyan.opacity(0.16), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.34), radius: 24, y: 14)
            )
    }
}

struct AppMark: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [GameTheme.coral, Color(red: 0.68, green: 0.08, blue: 0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            .rotationEffect(.degrees(8))
            .shadow(color: GameTheme.coral.opacity(0.35), radius: 8)

            VStack(alignment: .leading, spacing: 0) {
                Text("DODGE LAB")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                Text("TACTICAL TRAINING")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(GameTheme.cyan)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dodge Lab Tactical Training")
    }
}

struct ModeTag: View {
    let text: String
    var color: Color = GameTheme.cyan

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color, radius: 4)
            Text(text.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.5)
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.white.opacity(0.075), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.24), lineWidth: 1))
    }
}

struct MetricTile: View {
    let icon: String
    let title: String
    let value: String
    var accent: Color = GameTheme.cyan
    var badge: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(GameTheme.softText)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 7, weight: .black, design: .rounded))
                            .foregroundStyle(GameTheme.midnight)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(accent, in: Capsule())
                    }
                }

                Text(value)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }
}

struct GamePrimaryButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "arrow.right",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(GameTheme.midnight.opacity(0.68))
                    }
                }

                Spacer()

                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .black))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.25), in: Circle())
            }
            .foregroundStyle(GameTheme.midnight)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.83, blue: 0.30), GameTheme.gold],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: GameTheme.gold.opacity(0.28), radius: 16, y: 8)
        }
        .buttonStyle(GamePressButtonStyle())
    }
}

struct GameSecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.86))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.11), lineWidth: 1)
            }
        }
        .buttonStyle(GamePressButtonStyle())
    }
}

private struct GamePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}
