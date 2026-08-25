import SwiftUI

struct GrowthRecordView: View {
    let progress: PlayerProgress
    let bestSurvivalTime: TimeInterval
    let bestDodgedCount: Int
    let onClose: () -> Void

    @State private var appeared = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let scale = min(width / 1846, height / 852)
            let usesTabletComposition = UIDevice.current.userInterfaceIdiom == .pad
            // The full-bleed composition intentionally ignores safe areas. Reserve
            // room for the landscape sensor housing on modern, extra-wide iPhones.
            let protectsSensorHousing = !usesTabletComposition && width / max(1, height) > 2
            let overviewWidth: CGFloat = protectsSensorHousing ? 410 : 470
            let overviewCenterX: CGFloat = protectsSensorHousing ? 315 : 285
            let contentOffsetY = usesTabletComposition
                ? max(0, (height - 852 * scale) / 2)
                : 0

            ZStack {
                AdaptiveLandscapeArtwork(
                    imageName: "result_ledger_opaque_bg",
                    viewportSize: geometry.size,
                    usesTabletComposition: usesTabletComposition
                )

                Color(red: 0.96, green: 0.91, blue: 0.80)
                    .opacity(0.12)
                    .allowsHitTesting(false)

                header(scale: scale)
                    .frame(width: 1660 * scale, height: 92 * scale)
                    .position(x: 923 * scale, y: 72 * scale + contentOffsetY)

                overviewPanel(scale: scale)
                    .frame(width: overviewWidth * scale, height: 650 * scale)
                    .position(x: overviewCenterX * scale, y: 485 * scale + contentOffsetY)

                VStack(spacing: 24 * scale) {
                    trendPanel(scale: scale)
                        .frame(height: 350 * scale)
                    rankDistributionPanel(scale: scale)
                        .frame(height: 276 * scale)
                }
                .frame(width: 700 * scale, height: 650 * scale)
                .position(x: 900 * scale, y: 485 * scale + contentOffsetY)

                detailPanel(scale: scale)
                    .frame(width: 450 * scale, height: 650 * scale)
                    .position(x: 1530 * scale, y: 485 * scale + contentOffsetY)
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.88)) {
                appeared = true
            }
        }
    }

    private func header(scale: CGFloat) -> some View {
        HStack(spacing: 22 * scale) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 28 * scale, weight: .black))
                    .foregroundStyle(Color(red: 0.94, green: 0.90, blue: 0.79))
                    .frame(width: max(44, 62 * scale), height: max(44, 62 * scale))
                    .background(Color(red: 0.09, green: 0.085, blue: 0.075).opacity(0.94), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(GameTheme.gold.opacity(0.76), lineWidth: max(1.5, 2.5 * scale))
                    }
            }
            .buttonStyle(GrowthPressButtonStyle())
            .accessibilityLabel(L10n.text("progress.close"))

            VStack(alignment: .leading, spacing: 2 * scale) {
                Text(L10n.text("progress.title"))
                    .font(.system(size: 46 * scale, weight: .black, design: .rounded))
                    .tracking(-1.2 * scale)
                    .foregroundStyle(Color(red: 0.13, green: 0.105, blue: 0.07))
                    .lineLimit(1)

                Text(L10n.text("progress.subtitle"))
                    .font(.system(size: 17 * scale, weight: .bold, design: .rounded))
                    .tracking(1.2 * scale)
                    .foregroundStyle(Color(red: 0.34, green: 0.28, blue: 0.18).opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer()

            HStack(spacing: 10 * scale) {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 20 * scale, weight: .black))
                    .foregroundStyle(GameTheme.cyan)
                Text(L10n.text("progress.last_updated"))
                    .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.16, blue: 0.12).opacity(0.72))
            }
            .padding(.horizontal, 18 * scale)
            .padding(.vertical, 10 * scale)
            .background(Color.white.opacity(0.34), in: Capsule())
            .overlay(Capsule().stroke(GameTheme.gold.opacity(0.35), lineWidth: 1))
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -12 * scale)
    }

    private func overviewPanel(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            panelTitle(
                icon: "crown.fill",
                title: L10n.text("progress.overview"),
                accent: rankColor,
                scale: scale
            )

            VStack(spacing: 0) {
                Text(L10n.text("progress.current_peak"))
                    .font(.system(size: 16 * scale, weight: .black, design: .rounded))
                    .tracking(1.4 * scale)
                    .foregroundStyle(Color.black.opacity(0.54))

                Text(bestSurvivalTime > 0 ? bestRank.rawValue : "—")
                    .font(.system(
                        size: (bestRank == .ss ? 112 : 140) * scale,
                        weight: .black,
                        design: .serif
                    ))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [rankColor.opacity(0.98), rankColor.opacity(0.58)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .white.opacity(0.90), radius: 1 * scale, y: 1 * scale)
                    .shadow(color: .black.opacity(0.24), radius: 4 * scale, y: 5 * scale)
                    .frame(height: 142 * scale)

                Text(formattedBestTime)
                    .font(.system(size: 30 * scale, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.03, green: 0.43, blue: 0.49))
            }
            .frame(height: 208 * scale)

            ornamentDivider(scale: scale)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12 * scale), count: 2),
                spacing: 12 * scale
            ) {
                summaryMetric(
                    icon: "flag.checkered",
                    label: L10n.text("progress.total_runs"),
                    value: "\(progress.totalRuns)",
                    accent: GameTheme.coral,
                    scale: scale
                )
                summaryMetric(
                    icon: "timer",
                    label: L10n.text("progress.average_time"),
                    value: formattedAverageTime,
                    accent: GameTheme.cyan,
                    scale: scale
                )
                summaryMetric(
                    icon: "sparkles",
                    label: L10n.text("progress.total_dodged"),
                    value: compactNumber(progress.totalDodgedCount),
                    accent: GameTheme.violet,
                    scale: scale
                )
                summaryMetric(
                    icon: "scope",
                    label: L10n.text("progress.avoidance_rate"),
                    value: formattedAvoidanceRate,
                    accent: GameTheme.mint,
                    scale: scale
                )
            }
            .padding(.top, 18 * scale)

            HStack(spacing: 12 * scale) {
                Image(systemName: "hourglass")
                    .font(.system(size: 20 * scale, weight: .black))
                    .foregroundStyle(GameTheme.gold)
                Text(L10n.text("progress.total_time"))
                    .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.58))
                Spacer()
                Text(formattedTotalTime)
                    .font(.system(size: 23 * scale, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.13, green: 0.105, blue: 0.07))
            }
            .padding(.horizontal, 16 * scale)
            .frame(height: 64 * scale)
            .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 16 * scale))
            .padding(.top, 14 * scale)

            Spacer(minLength: 0)
        }
        .padding(24 * scale)
        .growthPanel(scale: scale)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -18 * scale)
    }

    private func trendPanel(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12 * scale) {
                panelTitle(
                    icon: "chart.line.uptrend.xyaxis",
                    title: L10n.text("progress.recent_trend"),
                    accent: GameTheme.cyan,
                    scale: scale
                )

                Spacer(minLength: 4 * scale)

                if let improvement = progress.averageImprovement {
                    trendBadge(improvement: improvement, scale: scale)
                }
            }

            if progress.recentTenRuns.isEmpty {
                emptyState(
                    icon: "chart.xyaxis.line",
                    title: L10n.text("progress.no_history"),
                    scale: scale
                )
            } else {
                ProgressLineChart(runs: progress.recentTenRuns, scale: scale)
                    .padding(.top, 8 * scale)

                HStack(spacing: 26 * scale) {
                    chartSummary(
                        label: L10n.text("progress.recent_average"),
                        value: L10n.format("format.seconds_short", progress.recentTenAverage),
                        accent: GameTheme.cyan,
                        scale: scale
                    )

                    chartSummary(
                        label: L10n.text("progress.recent_best"),
                        value: L10n.format(
                            "format.seconds_short",
                            progress.recentTenRuns.map(\.survivalTime).max() ?? 0
                        ),
                        accent: GameTheme.gold,
                        scale: scale
                    )
                }
                .padding(.top, 3 * scale)
            }
        }
        .padding(22 * scale)
        .growthPanel(scale: scale)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16 * scale)
    }

    private func rankDistributionPanel(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            panelTitle(
                icon: "chart.bar.fill",
                title: L10n.text("progress.rank_distribution"),
                accent: GameTheme.gold,
                scale: scale
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 12 * scale) {
                    ForEach(PerformanceRank.allCases) { rank in
                        rankBar(rank: rank, scale: scale)
                            .frame(width: 46 * scale)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.top, 16 * scale)
        }
        .padding(22 * scale)
        .growthPanel(scale: scale)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18 * scale)
    }

    private func detailPanel(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            panelTitle(
                icon: "gauge.with.dots.needle.67percent",
                title: L10n.text("progress.speed_records"),
                accent: GameTheme.cyan,
                scale: scale
            )

            VStack(spacing: 8 * scale) {
                ForEach(PlayerSpeedSetting.allCases) { speed in
                    speedRow(speed: speed, scale: scale)
                }
            }
            .padding(.top, 16 * scale)

            ornamentDivider(scale: scale)
                .padding(.vertical, 18 * scale)

            panelTitle(
                icon: "clock.arrow.circlepath",
                title: L10n.text("progress.recent_runs"),
                accent: GameTheme.coral,
                scale: scale
            )

            if progress.recentRuns.isEmpty {
                emptyState(
                    icon: "figure.run",
                    title: L10n.text("progress.no_runs"),
                    scale: scale
                )
            } else {
                VStack(spacing: 3 * scale) {
                    ForEach(Array(progress.recentRuns.suffix(3).reversed())) { run in
                        recentRunRow(run: run, scale: scale)
                    }
                }
                .padding(.top, 9 * scale)
            }

            Spacer(minLength: 0)
        }
        .padding(22 * scale)
        .growthPanel(scale: scale)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 18 * scale)
    }

    private func panelTitle(
        icon: String,
        title: String,
        accent: Color,
        scale: CGFloat
    ) -> some View {
        HStack(spacing: 10 * scale) {
            Image(systemName: icon)
                .font(.system(size: 20 * scale, weight: .black))
                .foregroundStyle(accent)
                .frame(width: 32 * scale, height: 32 * scale)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9 * scale))

            Text(title)
                .font(.system(size: 21 * scale, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.14, green: 0.115, blue: 0.08))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func summaryMetric(
        icon: String,
        label: String,
        value: String,
        accent: Color,
        scale: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            HStack(spacing: 7 * scale) {
                Image(systemName: icon)
                    .font(.system(size: 14 * scale, weight: .black))
                    .foregroundStyle(accent)
                Text(label)
                    .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.54))
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
            }
            Text(value)
                .font(.system(size: 27 * scale, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.12, green: 0.105, blue: 0.075))
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .padding(14 * scale)
        .frame(maxWidth: .infinity, minHeight: 87 * scale, alignment: .leading)
        .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 16 * scale))
        .overlay {
            RoundedRectangle(cornerRadius: 16 * scale)
                .stroke(accent.opacity(0.24), lineWidth: max(1, 1.5 * scale))
        }
    }

    private func trendBadge(improvement: TimeInterval, scale: CGFloat) -> some View {
        let isPositive = improvement >= 0
        let color = isPositive ? GameTheme.mint : GameTheme.coral
        return HStack(spacing: 6 * scale) {
            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
            Text(L10n.format("format.signed_seconds", improvement))
                .monospacedDigit()
        }
        .font(.system(size: 14 * scale, weight: .black, design: .rounded))
        .foregroundStyle(color)
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 7 * scale)
        .background(color.opacity(0.11), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
        .accessibilityLabel(
            L10n.format("progress.improvement_accessibility", improvement)
        )
    }

    private func chartSummary(
        label: String,
        value: String,
        accent: Color,
        scale: CGFloat
    ) -> some View {
        HStack(spacing: 8 * scale) {
            Circle()
                .fill(accent)
                .frame(width: 7 * scale, height: 7 * scale)
            Text(label)
                .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.52))
            Text(value)
                .font(.system(size: 17 * scale, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.12, green: 0.105, blue: 0.075))
        }
    }

    private func rankBar(rank: PerformanceRank, scale: CGFloat) -> some View {
        let count = progress.count(for: rank)
        let maximum = max(1, PerformanceRank.allCases.map(progress.count(for:)).max() ?? 1)
        let ratio = CGFloat(count) / CGFloat(maximum)
        let color = color(for: rank)

        return VStack(spacing: 6 * scale) {
            Text("\(count)")
                .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.black.opacity(0.58))

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.black.opacity(0.06))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.55), color],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: max(5 * scale, 102 * scale * ratio))
            }
            .frame(width: 35 * scale, height: 102 * scale)

            Text(rank.rawValue)
                .font(.system(size: 17 * scale, weight: .black, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func speedRow(speed: PlayerSpeedSetting, scale: CGFloat) -> some View {
        let speedRecord = progress.progress(for: speed)
        let hasRecord = speedRecord.playCount > 0
        return HStack(spacing: 12 * scale) {
            Circle()
                .fill(speedColor(speed).opacity(0.16))
                .frame(width: 34 * scale, height: 34 * scale)
                .overlay {
                    Image(systemName: speedIcon(speed))
                        .font(.system(size: 15 * scale, weight: .black))
                        .foregroundStyle(speedColor(speed))
                }

            VStack(alignment: .leading, spacing: 2 * scale) {
                Text(L10n.text("settings.speed.\(speed.rawValue)"))
                    .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.58))
                Text(hasRecord ? L10n.format("progress.plays_count", speedRecord.playCount) : L10n.text("progress.no_record"))
                    .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.40))
            }

            Spacer(minLength: 4 * scale)

            Text(hasRecord ? L10n.format("format.seconds_short", speedRecord.bestSurvivalTime) : "—")
                .font(.system(size: 22 * scale, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.04, green: 0.36, blue: 0.41))
        }
        .padding(.horizontal, 13 * scale)
        .frame(height: 61 * scale)
        .background(Color.white.opacity(0.27), in: RoundedRectangle(cornerRadius: 14 * scale))
        .overlay {
            RoundedRectangle(cornerRadius: 14 * scale)
                .stroke(speedColor(speed).opacity(0.22), lineWidth: 1)
        }
    }

    private func recentRunRow(run: GameRunRecord, scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            Text(run.rank.rawValue)
                .font(.system(size: 17 * scale, weight: .black, design: .rounded))
                .foregroundStyle(color(for: run.rank))
                .frame(width: 30 * scale)

            VStack(alignment: .leading, spacing: 1 * scale) {
                Text(run.playedAt.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 11 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.42))
                Text(L10n.text("settings.speed.\(run.playerSpeedSetting.rawValue)"))
                    .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.36))
            }

            Spacer(minLength: 2 * scale)

            Text(L10n.format("format.seconds_short", run.survivalTime))
                .font(.system(size: 19 * scale, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.12, green: 0.105, blue: 0.075))

            Text("• \(run.dodgedCount)")
                .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(GameTheme.coral)
        }
        .padding(.horizontal, 10 * scale)
        .frame(height: 46 * scale)
        .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 11 * scale))
    }

    private func emptyState(icon: String, title: String, scale: CGFloat) -> some View {
        VStack(spacing: 10 * scale) {
            Image(systemName: icon)
                .font(.system(size: 34 * scale, weight: .bold))
                .foregroundStyle(GameTheme.cyan.opacity(0.68))
            Text(title)
                .font(.system(size: 14 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.46))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ornamentDivider(scale: CGFloat) -> some View {
        HStack(spacing: 7 * scale) {
            Rectangle()
                .fill(GameTheme.gold.opacity(0.50))
                .frame(height: max(1, 1.2 * scale))
            Image(systemName: "diamond.fill")
                .font(.system(size: 8 * scale, weight: .black))
                .foregroundStyle(GameTheme.gold)
            Rectangle()
                .fill(GameTheme.gold.opacity(0.50))
                .frame(height: max(1, 1.2 * scale))
        }
    }

    private var bestRank: PerformanceRank {
        PerformanceRank(survivalTime: bestSurvivalTime)
    }

    private var rankColor: Color {
        color(for: bestRank)
    }

    private var formattedBestTime: String {
        bestSurvivalTime > 0 ? L10n.format("format.seconds_short", bestSurvivalTime) : "—"
    }

    private var formattedAverageTime: String {
        progress.totalRuns > 0
            ? L10n.format("format.seconds_short", progress.averageSurvivalTime)
            : "—"
    }

    private var formattedAvoidanceRate: String {
        progress.totalRuns > 0
            ? L10n.format("format.percent_whole", progress.overallAvoidanceRate * 100)
            : "—"
    }

    private var formattedTotalTime: String {
        let seconds = Int(progress.totalSurvivalTime.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return L10n.format("format.hours_minutes", hours, minutes)
        }
        return L10n.format("format.minutes_seconds", minutes, seconds % 60)
    }

    private func compactNumber(_ value: Int) -> String {
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return value.formatted()
    }

    private func color(for rank: PerformanceRank) -> Color {
        switch rank.tier {
        case .sss: return Color(red: 0.95, green: 0.28, blue: 0.50)
        case .ss: return GameTheme.violet
        case .s: return GameTheme.gold
        case .a: return GameTheme.mint
        case .b: return GameTheme.cyan
        case .c: return GameTheme.coral
        case .d: return Color(red: 0.46, green: 0.40, blue: 0.32)
        }
    }

    private func speedColor(_ speed: PlayerSpeedSetting) -> Color {
        switch speed {
        case .slow: return GameTheme.mint
        case .normal: return GameTheme.cyan
        case .fast: return GameTheme.gold
        case .ultraFast: return GameTheme.coral
        }
    }

    private func speedIcon(_ speed: PlayerSpeedSetting) -> String {
        switch speed {
        case .slow: return "tortoise.fill"
        case .normal: return "figure.run"
        case .fast: return "hare.fill"
        case .ultraFast: return "bolt.fill"
        }
    }
}

struct ProgressLineChart: View {
    let runs: [GameRunRecord]
    let scale: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let values = runs.map(\.survivalTime)
            let ceiling = max(10, ceil((values.max() ?? 0) / 10) * 10)
            let left = 42 * scale
            let right = 12 * scale
            let top = 14 * scale
            let bottom = 28 * scale
            let plotWidth = max(1, geometry.size.width - left - right)
            let plotHeight = max(1, geometry.size.height - top - bottom)

            ZStack(alignment: .topLeading) {
                ForEach(0..<4, id: \.self) { index in
                    let y = top + plotHeight * CGFloat(index) / 3
                    Path { path in
                        path.move(to: CGPoint(x: left, y: y))
                        path.addLine(to: CGPoint(x: left + plotWidth, y: y))
                    }
                    .stroke(Color.black.opacity(0.09), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                }

                if values.count > 1 {
                    areaPath(
                        values: values,
                        ceiling: ceiling,
                        left: left,
                        top: top,
                        plotWidth: plotWidth,
                        plotHeight: plotHeight
                    )
                    .fill(
                        LinearGradient(
                            colors: [GameTheme.cyan.opacity(0.24), GameTheme.cyan.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    linePath(
                        values: values,
                        ceiling: ceiling,
                        left: left,
                        top: top,
                        plotWidth: plotWidth,
                        plotHeight: plotHeight
                    )
                    .stroke(
                        LinearGradient(
                            colors: [GameTheme.cyan, Color(red: 0.03, green: 0.47, blue: 0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: max(2, 3 * scale), lineCap: .round, lineJoin: .round)
                    )
                }

                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let point = chartPoint(
                        index: index,
                        count: values.count,
                        value: value,
                        ceiling: ceiling,
                        left: left,
                        top: top,
                        plotWidth: plotWidth,
                        plotHeight: plotHeight
                    )
                    Circle()
                        .fill(index == values.count - 1 ? GameTheme.coral : GameTheme.cyan)
                        .frame(width: 8 * scale, height: 8 * scale)
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2 * scale))
                        .shadow(color: GameTheme.cyan.opacity(0.35), radius: 3 * scale)
                        .position(point)
                }

                Text(L10n.format("format.seconds_short", ceiling))
                    .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.60))
                    .position(x: 19 * scale, y: top + 4 * scale)

                Text("0")
                    .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.60))
                    .position(x: 24 * scale, y: top + plotHeight)

                HStack {
                    Text(L10n.text("progress.older"))
                    Spacer()
                    Text(L10n.text("progress.latest"))
                }
                .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.58))
                .frame(width: plotWidth)
                .position(x: left + plotWidth / 2, y: top + plotHeight + 18 * scale)
            }
        }
    }

    private func chartPoint(
        index: Int,
        count: Int,
        value: TimeInterval,
        ceiling: TimeInterval,
        left: CGFloat,
        top: CGFloat,
        plotWidth: CGFloat,
        plotHeight: CGFloat
    ) -> CGPoint {
        let xRatio = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0.5
        let yRatio = CGFloat(value / max(1, ceiling))
        return CGPoint(
            x: left + plotWidth * xRatio,
            y: top + plotHeight * (1 - yRatio)
        )
    }

    private func linePath(
        values: [TimeInterval],
        ceiling: TimeInterval,
        left: CGFloat,
        top: CGFloat,
        plotWidth: CGFloat,
        plotHeight: CGFloat
    ) -> Path {
        Path { path in
            for (index, value) in values.enumerated() {
                let point = chartPoint(
                    index: index,
                    count: values.count,
                    value: value,
                    ceiling: ceiling,
                    left: left,
                    top: top,
                    plotWidth: plotWidth,
                    plotHeight: plotHeight
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func areaPath(
        values: [TimeInterval],
        ceiling: TimeInterval,
        left: CGFloat,
        top: CGFloat,
        plotWidth: CGFloat,
        plotHeight: CGFloat
    ) -> Path {
        Path { path in
            path.move(to: CGPoint(x: left, y: top + plotHeight))
            for (index, value) in values.enumerated() {
                path.addLine(
                    to: chartPoint(
                        index: index,
                        count: values.count,
                        value: value,
                        ceiling: ceiling,
                        left: left,
                        top: top,
                        plotWidth: plotWidth,
                        plotHeight: plotHeight
                    )
                )
            }
            path.addLine(to: CGPoint(x: left + plotWidth, y: top + plotHeight))
            path.closeSubpath()
        }
    }
}

private extension View {
    func growthPanel(scale: CGFloat) -> some View {
        background(
            Color(red: 0.95, green: 0.90, blue: 0.79).opacity(0.90),
            in: RoundedRectangle(cornerRadius: 25 * scale, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 25 * scale, style: .continuous)
                .stroke(Color.black.opacity(0.56), lineWidth: max(1.5, 2.5 * scale))
                .padding(2 * scale)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 21 * scale, style: .continuous)
                .stroke(GameTheme.gold.opacity(0.46), lineWidth: max(1, 1.5 * scale))
                .padding(8 * scale)
        }
        .shadow(color: .black.opacity(0.20), radius: 10 * scale, y: 6 * scale)
    }
}

private struct GrowthPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("Growth Record") {
    GrowthRecordView(
        progress: .preview,
        bestSurvivalTime: 70.4,
        bestDodgedCount: 144,
        onClose: {}
    )
    .frame(width: 932, height: 430)
}
#endif
