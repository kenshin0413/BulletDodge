import SwiftUI

struct HomeView: View {
    let bestSurvivalTime: TimeInterval
    let bestDodgedCount: Int
    let joystickMode: JoystickMode
    let onJoystickModeChange: (JoystickMode) -> Void
    let playerSpeedSetting: PlayerSpeedSetting
    let onPlayerSpeedSettingChange: (PlayerSpeedSetting) -> Void
    let dodgeGuideEnabled: Bool
    let onDodgeGuideEnabledChange: (Bool) -> Void
    let isPrivacyOptionsRequired: Bool
    let onShowPrivacyOptions: () -> Void
    let rankingProfile: RankingProfile?
    let rankedRunsRemaining: Int
    let onShowAccount: () -> Void
    let onShowLeaderboard: () -> Void
    let onStartRanked: () -> Void
    let onStart: () -> Void

    @State private var appeared = false
    @State private var isShowingSettings = ProcessInfo.processInfo.environment[
        "BULLETDODGE_SHOW_SETTINGS"
    ] == "1"

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let scale = min(width / 1846, height / 852)
            let usesTabletComposition = UIDevice.current.userInterfaceIdiom == .pad
            let contentOffsetY = usesTabletComposition
                ? max(0, (height - 852 * scale) / 2)
                : 0
            let bottomRowY = height - 110 * scale
            let topControlDiameter = max(44, 82 * scale)
            let topControlStep = max(topControlDiameter + 4, 114 * scale)
            let topControlInset = max(42, 114 * scale)
            let topControlY = max(40, 93 * scale)
            let settingsCenterX = width - topControlInset
            let leaderboardCenterX = width - topControlInset - topControlStep
            let accountCenterX = width - topControlInset - topControlStep * 2

            ZStack {
                AdaptiveLandscapeArtwork(
                    imageName: "home_hero_battle_aligned",
                    viewportSize: geometry.size,
                    usesTabletComposition: usesTabletComposition
                )

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.28),
                        Color.black.opacity(0.10),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: UnitPoint(x: 0.48, y: 0.5)
                )
                .allowsHitTesting(false)

                brandLockup(scale: scale)
                    .frame(width: 760 * scale, alignment: .leading)
                    .position(
                        x: 515 * scale,
                        y: 286 * scale + contentOffsetY
                    )

                statsStrip(scale: scale)
                    .frame(width: 930 * scale, height: 76 * scale)
                    .position(
                        x: 575 * scale,
                        y: bottomRowY
                    )

                battleButtons(scale: scale)
                    .frame(width: 720 * scale, height: 92 * scale)
                    .position(
                        x: 1415 * scale,
                        y: bottomRowY
                    )

                settingsButton(scale: scale)
                    .frame(
                        width: topControlDiameter,
                        height: topControlDiameter
                    )
                    .position(
                        x: settingsCenterX,
                        y: topControlY
                    )
                    .zIndex(3)

                leaderboardButton(scale: scale)
                    .frame(
                        width: topControlDiameter,
                        height: topControlDiameter
                    )
                    .position(
                        x: leaderboardCenterX,
                        y: topControlY
                    )
                    .zIndex(3)

                accountButton(scale: scale)
                    .frame(
                        width: topControlDiameter,
                        height: topControlDiameter
                    )
                    .position(
                        x: accountCenterX,
                        y: topControlY
                    )
                    .zIndex(3)

                if isShowingSettings {
                    settingsOverlay(
                        width: width,
                        height: height,
                        scale: scale
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(10)
                }
            }
            .frame(width: width, height: height)
            .clipped()
            .animation(.easeInOut(duration: 0.20), value: isShowingSettings)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.88)) {
                appeared = true
            }
        }
    }

    private func brandLockup(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            ZStack(alignment: .leading) {
                Text(L10n.text("app.title"))
                    .font(.system(size: 188 * scale, weight: .black, design: .rounded))
                    .tracking(-9 * scale)
                    .foregroundStyle(GameTheme.coral.opacity(0.55))
                    .offset(x: 3 * scale, y: 4 * scale)

                Text(L10n.text("app.title"))
                    .font(.system(size: 188 * scale, weight: .black, design: .rounded))
                    .tracking(-9 * scale)
                    .foregroundStyle(Color(red: 0.98, green: 0.96, blue: 0.89))
                    .shadow(color: .black.opacity(0.45), radius: 5 * scale, y: 5 * scale)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.52)
            .allowsTightening(true)

            HStack(spacing: 14 * scale) {
                speedLines(color: GameTheme.cyan, scale: scale)

                Text(L10n.text("app.secondary_name"))
                    .font(.system(size: 62 * scale, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(Color(red: 0.97, green: 0.95, blue: 0.88))
                    .shadow(color: .black.opacity(0.35), radius: 3 * scale, y: 3 * scale)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                speedLines(color: GameTheme.coral, scale: scale)
            }

            Text(L10n.text("home.tagline"))
                .font(.system(size: 30 * scale, weight: .semibold, design: .rounded))
                .tracking(2.1 * scale)
                .foregroundStyle(.white.opacity(0.94))
                .shadow(color: .black.opacity(0.45), radius: 3 * scale, y: 2 * scale)
                .padding(.top, 18 * scale)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -24 * scale)
    }

    private func speedLines(color: Color, scale: CGFloat) -> some View {
        VStack(spacing: 5 * scale) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: (92 - CGFloat(index) * 13) * scale, height: 6 * scale)
            }
        }
    }

    private func statsStrip(scale: CGFloat) -> some View {
        HStack(spacing: 26 * scale) {
            statItem(
                icon: "crown.fill",
                label: L10n.text("stats.best_rank"),
                value: bestRankLetter,
                color: bestRankColor,
                scale: scale
            )

            Rectangle()
                .fill(.white.opacity(0.48))
                .frame(width: 1, height: 42 * scale)

            statItem(
                icon: "timer",
                label: L10n.text("stats.best_short"),
                value: formattedBestTime,
                color: GameTheme.cyan,
                scale: scale
            )

            Rectangle()
                .fill(.white.opacity(0.48))
                .frame(width: 1, height: 42 * scale)

            statItem(
                icon: "sparkles",
                label: L10n.text("stats.best_dodge"),
                value: bestDodgedCount == 0 ? "—" : "\(bestDodgedCount)",
                color: GameTheme.coral,
                scale: scale
            )
        }
        .padding(.horizontal, 28 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.72))
                .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 8 * scale, y: 4 * scale)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16 * scale)
    }

    private func statItem(
        icon: String,
        label: String,
        value: String,
        color: Color,
        scale: CGFloat
    ) -> some View {
        HStack(spacing: 16 * scale) {
            Image(systemName: icon)
                .font(.system(size: 31 * scale, weight: .bold))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 23 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)

            Text(value)
                .font(.system(size: 36 * scale, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private func startButton(scale: CGFloat) -> some View {
        Button(action: onStart) {
            HStack(spacing: 18 * scale) {
                Text(L10n.text("home.start"))
                    .font(.system(size: 38 * scale, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8 * scale)

                Image(systemName: "arrow.right")
                    .font(.system(size: 31 * scale, weight: .black))
            }
            .foregroundStyle(Color(red: 0.07, green: 0.055, blue: 0.04))
            .padding(.horizontal, 40 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.84, blue: 0.34),
                        Color(red: 0.94, green: 0.65, blue: 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.black.opacity(0.72), lineWidth: 3 * scale)
                    .padding(2 * scale)
            }
            .shadow(color: .black.opacity(0.28), radius: 8 * scale, y: 5 * scale)
        }
        .buttonStyle(HomePressButtonStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18 * scale)
        .accessibilityHint(L10n.text("home.start_hint"))
    }

    private func battleButtons(scale: CGFloat) -> some View {
        HStack(spacing: 16 * scale) {
            Button(action: onStart) {
                HStack(spacing: 14 * scale) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 25 * scale, weight: .black))
                        .frame(width: 48 * scale, height: 48 * scale)
                        .background(.black.opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 2 * scale) {
                        Text(L10n.text("home.practice_battle"))
                            .font(.system(size: 25 * scale, weight: .black, design: .rounded))
                        Text(L10n.text("home.practice_subtitle"))
                            .font(.system(size: 13 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.60))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                    Spacer(minLength: 5 * scale)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 19 * scale, weight: .black))
                        .frame(width: 36 * scale, height: 36 * scale)
                        .background(.black.opacity(0.10), in: Circle())
                }
                .foregroundStyle(Color(red: 0.07, green: 0.055, blue: 0.04))
                .padding(.horizontal, 17 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                            .fill(.black.opacity(0.32))
                            .offset(y: 5 * scale)
                        RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1.00, green: 0.87, blue: 0.40), Color(red: 0.95, green: 0.65, blue: 0.14)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                        .stroke(Color.black.opacity(0.72), lineWidth: 2.5 * scale)
                        .padding(2 * scale)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
                        .stroke(.white.opacity(0.34), lineWidth: 1.2 * scale)
                        .padding(7 * scale)
                }
                .shadow(color: .black.opacity(0.24), radius: 8 * scale, y: 5 * scale)
            }
            .buttonStyle(HomePressButtonStyle())
            .accessibilityHint(L10n.text("home.start_hint"))

            Button(action: onStartRanked) {
                HStack(spacing: 14 * scale) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 24 * scale, weight: .black))
                        .foregroundStyle(GameTheme.gold)
                        .frame(width: 48 * scale, height: 48 * scale)
                        .background(.black.opacity(0.18), in: Circle())

                    VStack(alignment: .leading, spacing: 1 * scale) {
                        Text(L10n.text("ranking.play_short"))
                            .font(.system(size: 25 * scale, weight: .black, design: .rounded))
                        Text(L10n.text("home.ranked_subtitle"))
                            .font(.system(size: 13 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                        Text(
                            rankedRunsRemaining > 0
                                ? L10n.format("ranking.reward.remaining", rankedRunsRemaining)
                                : L10n.text("ranking.reward.ad_required_short")
                        )
                            .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(rankedRunsRemaining > 0 ? GameTheme.gold : GameTheme.coral)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                    Spacer(minLength: 5 * scale)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 19 * scale, weight: .black))
                        .foregroundStyle(GameTheme.gold)
                        .frame(width: 36 * scale, height: 36 * scale)
                        .background(.black.opacity(0.18), in: Circle())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 17 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                            .fill(.black.opacity(0.38))
                            .offset(y: 5 * scale)
                        RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.05, green: 0.54, blue: 0.62), Color(red: 0.01, green: 0.27, blue: 0.34)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24 * scale, style: .continuous)
                        .stroke(.black.opacity(0.76), lineWidth: 2.5 * scale)
                        .padding(2 * scale)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
                        .stroke(GameTheme.gold.opacity(0.42), lineWidth: 1.2 * scale)
                        .padding(7 * scale)
                }
                .shadow(color: .black.opacity(0.28), radius: 8 * scale, y: 5 * scale)
            }
            .buttonStyle(HomePressButtonStyle())
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16 * scale)
    }

    private func settingsButton(scale: CGFloat) -> some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: max(20, 34 * scale), weight: .black))
                .foregroundStyle(Color(red: 0.98, green: 0.96, blue: 0.89))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.70), in: Circle())
                .overlay {
                    Circle()
                        .stroke(GameTheme.gold.opacity(0.90), lineWidth: max(1.5, 2.5 * scale))
                        .padding(2 * scale)
                }
                .shadow(color: .black.opacity(0.32), radius: 6 * scale, y: 3 * scale)
        }
        .buttonStyle(HomePressButtonStyle())
        .accessibilityLabel(L10n.text("settings.open"))
    }

    private func leaderboardButton(scale: CGFloat) -> some View {
        Button(action: onShowLeaderboard) {
            Image(systemName: "trophy.fill")
                .font(.system(size: max(19, 30 * scale), weight: .black))
                .foregroundStyle(GameTheme.gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.70), in: Circle())
                .overlay {
                    Circle()
                        .stroke(GameTheme.gold.opacity(0.88), lineWidth: max(1.5, 2.5 * scale))
                        .padding(2 * scale)
                }
                .shadow(color: .black.opacity(0.32), radius: 6 * scale, y: 3 * scale)
        }
        .buttonStyle(HomePressButtonStyle())
        .accessibilityLabel(L10n.text("ranking.open"))
    }

    private func accountButton(scale: CGFloat) -> some View {
        Button(action: onShowAccount) {
            ZStack {
                Circle().fill(Color.black.opacity(0.70))
                if let profile = rankingProfile {
                    RankingIconView(icon: profile.icon, size: max(40, 70 * scale))
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: max(19, 30 * scale), weight: .black))
                        .foregroundStyle(GameTheme.cyan)
                }
            }
            .overlay {
                Circle()
                    .stroke(GameTheme.cyan.opacity(0.88), lineWidth: max(1.5, 2.5 * scale))
                    .padding(2 * scale)
            }
            .shadow(color: .black.opacity(0.32), radius: 6 * scale, y: 3 * scale)
        }
        .buttonStyle(HomePressButtonStyle())
        .accessibilityLabel(L10n.text("account.open"))
    }

    private func settingsOverlay(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat
    ) -> some View {
        ZStack {
            Color.black.opacity(0.58)
                .contentShape(Rectangle())
                .onTapGesture {
                    isShowingSettings = false
                }

            VStack(spacing: 18 * scale) {
                HStack(spacing: 12 * scale) {
                    VStack(alignment: .leading, spacing: 3 * scale) {
                        Text(L10n.text("settings.title"))
                            .font(.system(
                                size: max(18, 46 * scale),
                                weight: .black,
                                design: .rounded
                            ))
                            .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.07))

                        Text(L10n.text("settings.joystick_title"))
                            .font(.system(
                                size: max(11, 23 * scale),
                                weight: .bold,
                                design: .rounded
                            ))
                            .foregroundStyle(Color.black.opacity(0.58))
                    }

                    Spacer(minLength: 8 * scale)

                    if isPrivacyOptionsRequired {
                        Button(action: onShowPrivacyOptions) {
                            HStack(spacing: 6 * scale) {
                                Image(systemName: "hand.raised.fill")
                                Text(L10n.text("settings.privacy_options"))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            .font(.system(
                                size: max(10, 18 * scale),
                                weight: .black,
                                design: .rounded
                            ))
                            .foregroundStyle(Color(red: 0.14, green: 0.11, blue: 0.07))
                            .padding(.horizontal, 12 * scale)
                            .frame(minHeight: max(34, 48 * scale))
                            .background(Color.white.opacity(0.34), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(GameTheme.gold.opacity(0.56), lineWidth: max(1, 2 * scale))
                            }
                        }
                        .buttonStyle(HomePressButtonStyle())
                    }

                    Button {
                        isShowingSettings = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: max(16, 25 * scale), weight: .black))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .frame(width: max(40, 58 * scale), height: max(40, 58 * scale))
                            .background(Color.black.opacity(0.80), in: Circle())
                    }
                    .buttonStyle(HomePressButtonStyle())
                    .accessibilityLabel(L10n.text("settings.close"))
                }

                HStack(spacing: 18 * scale) {
                    joystickModeButton(
                        mode: .fixed,
                        icon: "dot.circle.fill",
                        scale: scale
                    )

                    joystickModeButton(
                        mode: .floating,
                        icon: "hand.draw.fill",
                        scale: scale
                    )
                }

                playerSpeedSelector(scale: scale)

                dodgeGuideToggle(scale: scale)
            }
            .padding(.horizontal, 34 * scale)
            .padding(.vertical, 26 * scale)
            .frame(
                width: min(width - 28, 980 * scale),
                height: min(height - 24, 700 * scale)
            )
            .background(
                Color(red: 0.93, green: 0.88, blue: 0.76),
                in: RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                    .stroke(Color.black.opacity(0.78), lineWidth: max(2, 4 * scale))
                    .padding(3 * scale)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26 * scale, style: .continuous)
                    .stroke(GameTheme.gold.opacity(0.72), lineWidth: max(1, 2 * scale))
                    .padding(9 * scale)
            }
            .shadow(color: .black.opacity(0.42), radius: 20 * scale, y: 10 * scale)
        }
        .frame(width: width, height: height)
    }

    private func joystickModeButton(
        mode: JoystickMode,
        icon: String,
        scale: CGFloat
    ) -> some View {
        let isSelected = joystickMode == mode

        return Button {
            onJoystickModeChange(mode)
        } label: {
            VStack(spacing: 8 * scale) {
                HStack(spacing: 9 * scale) {
                    Image(systemName: icon)
                        .font(.system(size: max(17, 31 * scale), weight: .black))
                        .foregroundStyle(
                            GameTheme.cyan.opacity(isSelected ? 1 : 0.76)
                        )

                    Text(L10n.text("settings.joystick.\(mode.rawValue)"))
                        .font(.system(
                            size: max(13, 29 * scale),
                            weight: .black,
                            design: .rounded
                        ))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: max(16, 27 * scale), weight: .bold))
                        .foregroundStyle(isSelected ? GameTheme.gold : Color.black.opacity(0.28))
                }

                Text(L10n.text("settings.joystick.\(mode.rawValue)_description"))
                    .font(.system(
                        size: max(10, 19 * scale),
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.black.opacity(0.58))
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(isSelected ? Color.white : Color(red: 0.14, green: 0.11, blue: 0.07))
            .padding(.horizontal, 20 * scale)
            .padding(.vertical, 15 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isSelected
                    ? Color(red: 0.07, green: 0.12, blue: 0.14).opacity(0.96)
                    : Color.white.opacity(0.34),
                in: RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
                    .stroke(
                        isSelected ? GameTheme.cyan.opacity(0.86) : GameTheme.gold.opacity(0.46),
                        lineWidth: max(1.5, 2.5 * scale)
                    )
            }
        }
        .buttonStyle(HomePressButtonStyle())
        .accessibilityValue(
            isSelected ? L10n.text("settings.selected") : ""
        )
    }

    private func playerSpeedSelector(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack(spacing: 8 * scale) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: max(13, 22 * scale), weight: .black))
                    .foregroundStyle(GameTheme.cyan)

                Text(L10n.text("settings.speed_title"))
                    .font(.system(
                        size: max(12, 23 * scale),
                        weight: .black,
                        design: .rounded
                    ))
                    .foregroundStyle(Color(red: 0.14, green: 0.11, blue: 0.07))

                Spacer(minLength: 0)
            }

            HStack(spacing: 8 * scale) {
                ForEach(PlayerSpeedSetting.allCases) { setting in
                    playerSpeedButton(setting: setting, scale: scale)
                }
            }
        }
    }

    private func playerSpeedButton(
        setting: PlayerSpeedSetting,
        scale: CGFloat
    ) -> some View {
        let isSelected = playerSpeedSetting == setting

        return Button {
            onPlayerSpeedSettingChange(setting)
        } label: {
            Text(L10n.text("settings.speed.\(setting.rawValue)"))
                .font(.system(
                    size: max(10, 19 * scale),
                    weight: .black,
                    design: .rounded
                ))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : Color(red: 0.14, green: 0.11, blue: 0.07)
                )
                .frame(maxWidth: .infinity, minHeight: max(34, 58 * scale))
                .background(
                    isSelected
                        ? Color(red: 0.07, green: 0.12, blue: 0.14).opacity(0.96)
                        : Color.white.opacity(0.34),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            isSelected
                                ? GameTheme.cyan.opacity(0.88)
                                : GameTheme.gold.opacity(0.44),
                            lineWidth: max(1, 2 * scale)
                        )
                }
        }
        .buttonStyle(HomePressButtonStyle())
        .accessibilityValue(
            isSelected ? L10n.text("settings.selected") : ""
        )
    }

    private func dodgeGuideToggle(scale: CGFloat) -> some View {
        HStack(spacing: 13 * scale) {
            Image(systemName: "scope")
                .font(.system(size: max(16, 27 * scale), weight: .black))
                .foregroundStyle(GameTheme.cyan)
                .frame(width: max(28, 42 * scale))

            VStack(alignment: .leading, spacing: 2 * scale) {
                Text(L10n.text("settings.dodge_guide_title"))
                    .font(.system(
                        size: max(12, 22 * scale),
                        weight: .black,
                        design: .rounded
                    ))
                    .foregroundStyle(Color(red: 0.14, green: 0.11, blue: 0.07))

                Text(L10n.text("settings.dodge_guide_description"))
                    .font(.system(
                        size: max(9, 16 * scale),
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(Color.black.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 4 * scale)

            Toggle(
                "",
                isOn: Binding(
                    get: { dodgeGuideEnabled },
                    set: onDodgeGuideEnabledChange
                )
            )
            .labelsHidden()
            .tint(GameTheme.cyan)
            .scaleEffect(max(0.82, min(1.12, scale)))
            .accessibilityLabel(L10n.text("settings.dodge_guide_title"))
        }
        .padding(.horizontal, 18 * scale)
        .frame(minHeight: max(48, 70 * scale))
        .background(
            Color.white.opacity(0.30),
            in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                .stroke(GameTheme.gold.opacity(0.42), lineWidth: max(1, 2 * scale))
        }
    }

    private var formattedBestTime: String {
        guard bestSurvivalTime > 0 else { return "—" }
        return L10n.format("format.seconds_short", bestSurvivalTime)
    }

    private var bestRankLetter: String {
        guard bestSurvivalTime > 0 else { return "—" }
        switch bestSurvivalTime {
        case 68...: return "SS"
        case 45...: return "S"
        case 35...: return "A"
        case 20...: return "B"
        case 10...: return "C"
        default: return "D"
        }
    }

    private var bestRankColor: Color {
        switch bestRankLetter {
        case "SS": return GameTheme.violet
        case "S": return GameTheme.gold
        case "A": return GameTheme.mint
        case "B": return GameTheme.cyan
        case "C": return GameTheme.coral
        case "D": return GameTheme.softText
        default: return .white.opacity(0.72)
        }
    }
}

private struct HomePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

#Preview("Landscape Japanese") {
    HomeView(
        bestSurvivalTime: 41.7,
        bestDodgedCount: 93,
        joystickMode: .floating,
        onJoystickModeChange: { _ in },
        playerSpeedSetting: .normal,
        onPlayerSpeedSettingChange: { _ in },
        dodgeGuideEnabled: true,
        onDodgeGuideEnabledChange: { _ in },
        isPrivacyOptionsRequired: true,
        onShowPrivacyOptions: {},
        rankingProfile: nil,
        rankedRunsRemaining: 3,
        onShowAccount: {},
        onShowLeaderboard: {},
        onStartRanked: {},
        onStart: {}
    )
        .frame(width: 932, height: 430)
}
