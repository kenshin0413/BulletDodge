import SwiftUI

struct AccountView: View {
    @ObservedObject var service: RankingService
    @ObservedObject var rewardAccessManager: RewardAccessManager
    @ObservedObject var rewardedAdManager: RewardedAdManager
    let progress: PlayerProgress
    let bestSurvivalTime: TimeInterval
    let bestDodgedCount: Int
    let onClose: () -> Void

    @State private var name = ""
    @State private var icon: ProfileIcon = .shield
    @State private var isSaving = false
    @State private var message: String?
    @State private var didSave = false
    @State private var appeared = false
    @State private var isShowingIconPicker = ProcessInfo.processInfo.environment["BULLETDODGE_SHOW_ICON_PICKER"] == "1"
    @State private var pendingIcon: ProfileIcon = .shield
    @State private var isShowingNameRewardPrompt = false
    @State private var pendingRewardedName: String?
    @State private var pendingRewardedIcon: ProfileIcon?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 1846, geometry.size.height / 852)
            let offsetY = UIDevice.current.userInterfaceIdiom == .pad
                ? max(0, (geometry.size.height - 852 * scale) / 2)
                : 0
            // The aspect-filled ledger leaves extra vertical canvas on iPad.
            // Keeping all of that space above the account stack makes the
            // screen feel bottom-heavy, so reclaim a small, scale-aware amount.
            // Phones retain their already-approved zero-offset composition.
            let tabletContentLift = UIDevice.current.userInterfaceIdiom == .pad
                ? min(offsetY, 72 * scale)
                : 0

            ZStack {
                accountBackground(size: geometry.size)

                VStack(spacing: 18 * scale) {
                    accountHeader(scale: scale)
                        .frame(height: 70 * scale)

                    HStack(spacing: 22 * scale) {
                        profileEditor(scale: scale)
                            .frame(width: 650 * scale)
                        growthDashboard(scale: scale)
                    }
                    .frame(height: 680 * scale)
                }
                .padding(.leading, rankingSideInset(geometry, scale: scale))
                .padding(.trailing, max(54 * scale, geometry.safeAreaInsets.trailing + 16 * scale))
                .padding(.top, 34 * scale + offsetY - tabletContentLift)
                .padding(.bottom, 32 * scale)

                if isShowingIconPicker {
                    ProfileIconPickerOverlay(
                        selection: $pendingIcon,
                        availableIcons: service.profile?.availableIcons ?? ProfileIcon.standardCases,
                        scale: scale,
                        onCancel: { withAnimation(.easeOut(duration: 0.18)) { isShowingIconPicker = false } },
                        onConfirm: {
                            icon = pendingIcon
                            didSave = false
                            message = nil
                            withAnimation(.easeOut(duration: 0.18)) { isShowingIconPicker = false }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
                }
            }
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .statusBarHidden(true)
        .onAppear {
            synchronizeDraft()
#if DEBUG
            if ProcessInfo.processInfo.environment[
                "BULLETDODGE_PREVIEW_NAME_CHANGE"
            ] == "1", service.profile != nil {
                name = "NewPlayer"
            }
#endif
            if isShowingIconPicker { pendingIcon = icon }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
                appeared = true
            }
        }
        .alert(
            L10n.text("account.reward.title"),
            isPresented: $isShowingNameRewardPrompt
        ) {
            Button(L10n.text("common.cancel"), role: .cancel) {
                clearPendingNameReward()
            }
            Button(L10n.text("account.watch_to_change_name")) {
                rewardAccessManager.confirmNameChangeRewardExplanation()
                watchPendingRewardForNameChange()
            }
        } message: {
            Text(L10n.text("account.reward.message"))
        }
    }

    private func accountHeader(scale: CGFloat) -> some View {
        HStack(spacing: 20 * scale) {
            rankingBackButton(scale: scale, action: onClose)
            VStack(alignment: .leading, spacing: 1 * scale) {
                Text(L10n.text("account.manage_eyebrow"))
                    .rankingEyebrow(color: GameTheme.coral, scale: scale)
                Text(L10n.text("account.manage_title"))
                    .font(.system(size: 39 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(RankingPalette.ink)
                    .shadow(color: .white.opacity(0.72), radius: 3 * scale, y: 2 * scale)
            }
            Spacer()
            Label(L10n.text("progress.last_updated"), systemImage: "clock.arrow.2.circlepath")
                .font(.system(size: 17 * scale, weight: .black, design: .rounded))
                .foregroundStyle(RankingPalette.ink.opacity(0.82))
                .padding(.horizontal, 16 * scale)
                .frame(minHeight: 38 * scale)
                .background(.white.opacity(0.62), in: Capsule())
                .overlay(Capsule().stroke(GameTheme.gold.opacity(0.58), lineWidth: 1))
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -10 * scale)
    }

    private func profileEditor(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                HStack(alignment: .top, spacing: 26 * scale) {
                    Button(action: showIconPicker) {
                        ZStack(alignment: .bottomTrailing) {
                            Circle().stroke(GameTheme.gold.opacity(0.25), lineWidth: 2 * scale)
                                .frame(width: 220 * scale, height: 220 * scale)
                            Circle().stroke(GameTheme.cyan.opacity(0.20), lineWidth: 2 * scale)
                                .frame(width: 192 * scale, height: 192 * scale)
                            RankingIconView(icon: icon, size: 160 * scale)
                            iconEditBadge(scale: scale)
                                .offset(x: -13 * scale, y: -10 * scale)
                        }
                    }
                    .buttonStyle(RankingPressStyle())

                    VStack(alignment: .leading, spacing: 9 * scale) {
                        Text(previewName)
                            .font(.system(size: 43 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(RankingPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.52)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(L10n.text("account.public_identity"))
                            .font(.system(size: 17 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.62))
                            .lineLimit(2)
                            .minimumScaleFactor(0.76)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(L10n.text("account.change_icon"), systemImage: "hand.tap.fill")
                            .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.03, green: 0.35, blue: 0.40))
                            .padding(.horizontal, 13 * scale)
                            .frame(minHeight: 34 * scale)
                            .background(GameTheme.cyan.opacity(0.11), in: Capsule())
                            .overlay(Capsule().stroke(GameTheme.cyan.opacity(0.28), lineWidth: 1.2 * scale))
                    }
                    .padding(.top, 68 * scale)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(L10n.text("account.player_card"))
                    .rankingEyebrow(color: GameTheme.coral, scale: scale)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(height: 250 * scale)

            accentRule(scale: scale)
                .padding(.vertical, 15 * scale)

            editorLabel(L10n.text("account.enter_name"), icon: "character.cursor.ibeam", scale: scale)
            HStack(spacing: 12 * scale) {
                Image(systemName: "person.fill")
                    .font(.system(size: 23 * scale, weight: .black))
                    .foregroundStyle(GameTheme.cyan)
                TextField(L10n.text("account.name_placeholder"), text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { isNameFocused = false }
                    .onChange(of: name) { _, _ in
                        didSave = false
                        message = nil
                    }
                    .font(.system(size: 27 * scale, weight: .bold, design: .rounded))
                Image(systemName: RankingNameValidator.isValid(name) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 22 * scale, weight: .black))
                    .foregroundStyle(RankingNameValidator.isValid(name) ? GameTheme.cyan : GameTheme.coral)
            }
            .padding(.horizontal, 18 * scale)
            .frame(height: 68 * scale)
            .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 16 * scale))
            .overlay {
                RoundedRectangle(cornerRadius: 16 * scale)
                    .stroke(isNameFocused ? GameTheme.cyan : .black.opacity(0.16), lineWidth: 2 * scale)
            }
            .padding(.top, 10 * scale)

            Spacer(minLength: 14 * scale)

            HStack(alignment: .center, spacing: 12 * scale) {
                Image(systemName: didSave ? "checkmark.seal.fill" : "info.circle.fill")
                    .foregroundStyle(didSave ? GameTheme.mint : (message == nil ? .black.opacity(0.64) : GameTheme.coral))
                Text(message ?? L10n.text("account.name_rule"))
                    .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(didSave ? GameTheme.mint : (message == nil ? .black.opacity(0.68) : GameTheme.coral))
                    .lineLimit(2)
                Spacer(minLength: 6 * scale)
                Button {
                    isNameFocused = false
                    if requiresRewardForNameChange {
                        requestRewardForNameChange()
                    } else {
                        Task { await save() }
                    }
                } label: {
                    HStack(spacing: 10 * scale) {
                        if isSaving || rewardedAdManager.isPresenting {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: requiresRewardForNameChange ? "play.rectangle.fill" : "checkmark")
                        }
                        Text(L10n.text(saveActionTitleKey))
                    }
                    .font(.system(size: 20 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(RankingPalette.ink)
                    .padding(.horizontal, 22 * scale)
                    .frame(height: 55 * scale)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.84, blue: 0.34), Color(red: 0.93, green: 0.63, blue: 0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16 * scale)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16 * scale).stroke(.black.opacity(0.58), lineWidth: 2 * scale))
                }
                .buttonStyle(RankingPressStyle())
                .disabled(isSaving || rewardedAdManager.isPresenting || !RankingNameValidator.isValid(name) || !hasChanges)
                .opacity(RankingNameValidator.isValid(name) && hasChanges ? 1 : 0.48)
            }

            Spacer(minLength: 14 * scale)
            Label(L10n.text("ranking.account_note"), systemImage: "iphone.gen3")
                .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.64))
        }
        .padding(24 * scale)
        .accountSurface(accent: GameTheme.cyan, scale: scale)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -18 * scale)
    }

    private func growthDashboard(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14 * scale) {
            HStack {
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(L10n.text("progress.title"))
                        .font(.system(size: 31 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(RankingPalette.ink)
                    Text(L10n.text("progress.subtitle"))
                        .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.64))
                }
                Spacer()
                Text(bestSurvivalTime > 0 ? PerformanceRank(survivalTime: bestSurvivalTime).rawValue : "—")
                    .font(.system(size: 48 * scale, weight: .black, design: .serif))
                    .foregroundStyle(rankColor)
                Text(formattedBestTime)
                    .font(.system(size: 24 * scale, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GameTheme.cyan)
            }

            HStack(spacing: 10 * scale) {
                growthMetric("flag.checkered", L10n.text("progress.total_runs"), "\(progress.totalRuns)", GameTheme.coral, scale)
                growthMetric("timer", L10n.text("progress.average_time"), formattedAverageTime, GameTheme.cyan, scale)
                growthMetric("sparkles", L10n.text("progress.total_dodged"), compactNumber(progress.totalDodgedCount), GameTheme.violet, scale)
                growthMetric("scope", L10n.text("progress.avoidance_rate"), formattedAvoidanceRate, GameTheme.mint, scale)
            }

            HStack(spacing: 14 * scale) {
                VStack(alignment: .leading, spacing: 8 * scale) {
                    Label(L10n.text("progress.recent_trend"), systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 19 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(RankingPalette.ink)
                    if progress.recentTenRuns.isEmpty {
                        Spacer()
                        Text(L10n.text("progress.no_history"))
                            .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.62))
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ProgressLineChart(runs: progress.recentTenRuns, scale: scale)
                    }
                }
                .padding(16 * scale)
                .accountInnerSurface(scale: scale)

                VStack(alignment: .leading, spacing: 8 * scale) {
                    Label(L10n.text("progress.rank_distribution"), systemImage: "chart.bar.fill")
                        .font(.system(size: 19 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(RankingPalette.ink)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 9 * scale) {
                            ForEach(PerformanceRank.allCases) { rank in
                                rankColumn(rank, scale: scale)
                                    .frame(width: 34 * scale)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .padding(16 * scale)
                .frame(width: 350 * scale)
                .accountInnerSurface(scale: scale)
            }

            HStack {
                Label(L10n.text("progress.total_time"), systemImage: "hourglass")
                Spacer()
                Text(formattedTotalTime).monospacedDigit()
            }
            .font(.system(size: 18 * scale, weight: .black, design: .rounded))
            .foregroundStyle(RankingPalette.ink)
            .padding(.horizontal, 17 * scale)
            .frame(height: 50 * scale)
            .background(GameTheme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 14 * scale))
        }
        .padding(22 * scale)
        .accountSurface(accent: GameTheme.gold, scale: scale)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 18 * scale)
    }

    private func editorLabel(_ title: String, icon: String, scale: CGFloat) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 18 * scale, weight: .black, design: .rounded))
            .foregroundStyle(RankingPalette.ink)
    }

    private func growthMetric(_ icon: String, _ label: String, _ value: String, _ accent: Color, _ scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Label(label, systemImage: icon)
                .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(value)
                .font(.system(size: 24 * scale, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(12 * scale)
        .frame(maxWidth: .infinity, minHeight: 72 * scale, alignment: .leading)
        .background(.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 14 * scale))
        .overlay(RoundedRectangle(cornerRadius: 14 * scale).stroke(accent.opacity(0.26), lineWidth: 1.5 * scale))
    }

    private func rankColumn(_ rank: PerformanceRank, scale: CGFloat) -> some View {
        let count = progress.count(for: rank)
        let maximum = max(1, PerformanceRank.allCases.map(progress.count(for:)).max() ?? 1)
        let height = max(5 * scale, 92 * scale * CGFloat(count) / CGFloat(maximum))
        return VStack(spacing: 4 * scale) {
            Text("\(count)")
                .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.62))
            Capsule().fill(color(for: rank)).frame(width: 24 * scale, height: height)
            Text(rank.rawValue)
                .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                .foregroundStyle(color(for: rank))
        }
        .frame(maxWidth: .infinity)
    }

    private var previewName: String {
        let normalized = RankingNameValidator.normalizedDisplayName(name)
        return normalized.isEmpty ? L10n.text("account.preview_name") : normalized
    }

    private var hasChanges: Bool {
        guard let profile = service.profile else {
            return RankingNameValidator.isValid(name)
        }
        return RankingNameValidator.normalizedDisplayName(name) != profile.displayName || icon != profile.icon
    }

    private var isChangingName: Bool {
        guard let profile = service.profile else { return false }
        return RankingNameValidator.normalizedDisplayName(name) != profile.displayName
    }

    private var requiresRewardForNameChange: Bool {
        service.profile != nil && isChangingName && !rewardAccessManager.hasNameChangeCredit
    }

    private var saveActionTitleKey: String {
        if service.profile == nil { return "account.create" }
        if requiresRewardForNameChange { return "account.watch_to_change_name" }
        return "account.save_changes"
    }

    private func requestRewardForNameChange() {
        pendingRewardedName = name
        pendingRewardedIcon = icon
        if rewardAccessManager.hasConfirmedNameChangeReward {
            watchPendingRewardForNameChange()
        } else {
            isShowingNameRewardPrompt = true
        }
    }

    private func watchPendingRewardForNameChange() {
        guard let requestedName = pendingRewardedName,
              let requestedIcon = pendingRewardedIcon else { return }
        // Presenting a full-screen ad can make this view appear again and
        // synchronize its draft from the still-current profile. Keep the
        // exact values the user approved before the ad so the earned reward
        // updates that draft rather than leaving behind an unused credit.
        rewardedAdManager.present { outcome in
            clearPendingNameReward()
            switch outcome {
            case .earned:
                rewardAccessManager.grantNameChangeCredit()
                Task {
                    await save(
                        displayName: requestedName,
                        icon: requestedIcon
                    )
                }
            case .unavailable:
                message = L10n.text("reward.error.unavailable")
            case .dismissedWithoutReward:
                message = L10n.text("reward.error.not_completed")
            case .failedToPresent:
                message = L10n.text("reward.error.failed")
            }
        }
    }

    private func clearPendingNameReward() {
        pendingRewardedName = nil
        pendingRewardedIcon = nil
    }

    private func showIconPicker() {
        isNameFocused = false
        pendingIcon = icon
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isShowingIconPicker = true
        }
    }

    private var formattedBestTime: String {
        bestSurvivalTime > 0 ? L10n.format("format.seconds_short", bestSurvivalTime) : "—"
    }

    private var formattedAverageTime: String {
        progress.totalRuns > 0 ? L10n.format("format.seconds_short", progress.averageSurvivalTime) : "—"
    }

    private var formattedAvoidanceRate: String {
        progress.totalRuns > 0 ? L10n.format("format.percent_whole", progress.overallAvoidanceRate * 100) : "—"
    }

    private var formattedTotalTime: String {
        let seconds = Int(progress.totalSurvivalTime.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0
            ? L10n.format("format.hours_minutes", hours, minutes)
            : L10n.format("format.minutes_seconds", minutes, seconds % 60)
    }

    private var rankColor: Color { color(for: PerformanceRank(survivalTime: bestSurvivalTime)) }

    private func compactNumber(_ value: Int) -> String {
        value >= 10_000 ? String(format: "%.1fK", Double(value) / 1_000) : value.formatted()
    }

    private func color(for rank: PerformanceRank) -> Color {
        switch rank.tier {
        case .sss: Color(red: 0.95, green: 0.28, blue: 0.50)
        case .ss: GameTheme.violet
        case .s: GameTheme.gold
        case .a: GameTheme.mint
        case .b: GameTheme.cyan
        case .c: GameTheme.coral
        case .d: Color(red: 0.46, green: 0.40, blue: 0.32)
        }
    }

    private func synchronizeDraft() {
        guard let profile = service.profile else { return }
        name = profile.displayName
        icon = profile.icon
    }

    private func save(
        displayName requestedName: String? = nil,
        icon requestedIcon: ProfileIcon? = nil
    ) async {
        let targetName = requestedName ?? name
        let targetIcon = requestedIcon ?? icon
        let normalizedTargetName = RankingNameValidator.normalizedDisplayName(targetName)
        let targetHasChanges: Bool
        if let profile = service.profile {
            targetHasChanges = normalizedTargetName != profile.displayName
                || targetIcon != profile.icon
        } else {
            targetHasChanges = RankingNameValidator.isValid(targetName)
        }

        guard !isSaving,
              RankingNameValidator.isValid(targetName),
              targetHasChanges else { return }
        let consumesNameChangeCredit = service.profile != nil
            && normalizedTargetName != service.profile?.displayName
        guard !consumesNameChangeCredit || rewardAccessManager.hasNameChangeCredit else {
            message = L10n.text("account.reward_required")
            return
        }
        isSaving = true
        message = nil
        didSave = false
        defer { isSaving = false }
        do {
            if service.profile == nil {
                try await service.createProfile(displayName: targetName, icon: targetIcon)
            } else {
                try await service.updateProfile(displayName: targetName, icon: targetIcon)
            }
            name = service.profile?.displayName ?? normalizedTargetName
            icon = service.profile?.icon ?? targetIcon
            if consumesNameChangeCredit {
                rewardAccessManager.consumeNameChangeCredit()
            }
            didSave = true
            message = L10n.text("account.saved")
        } catch {
            message = error.localizedDescription
        }
    }
}

struct LeaderboardView: View {
    @ObservedObject var service: RankingService
    let rankedRunsRemaining: Int
    let presentsPersonalBestPlacement: Bool
    let onPlayRanked: () -> Void
    let onCreateAccount: () -> Void
    let onClose: () -> Void

    @State private var didPlayPersonalBestPlacement = false
    @State private var displayedLeaderboard: [LeaderboardEntry] = []
    @State private var isAnimatingPersonalBestEntry = false

    var body: some View {
        GeometryReader { geometry in
            let artworkWidth: CGFloat = 1846
            let artworkHeight: CGFloat = 852
            // Measured from result_ledger_opaque_bg.png. Keeping this at the
            // actual centre of the engraved spine is important on iPad, where
            // the full-bleed background is horizontally cropped.
            let authoredDividerX: CGFloat = 688
            let authoredBackButtonCenterX: CGFloat = 140
            let scale = min(geometry.size.width / artworkWidth, geometry.size.height / artworkHeight)
            let artworkOriginY = (geometry.size.height - 852 * scale) / 2
            // The full-bleed background uses aspect-fill while the live UI keeps
            // its existing device-specific size. Resolve the ledger divider in
            // the background's actual screen coordinates, then preserve every
            // authored UI offset from that divider. This prevents the line from
            // drifting through the left cards on iPad without shrinking the UI.
            let backgroundScale = max(
                geometry.size.width / artworkWidth,
                geometry.size.height / artworkHeight
            )
            let backgroundOriginX = (geometry.size.width - artworkWidth * backgroundScale) / 2
            let dividerScreenX = backgroundOriginX + authoredDividerX * backgroundScale
            let desiredPlayerSummaryCenterX = dividerScreenX
                - (authoredDividerX - 360) * scale
            // Preserve the reference offset from the spine whenever it fits.
            // On the tallest iPads, aspect-fill crops more of the artwork's
            // left page; clamp only enough to keep the full 500-unit summary
            // and its authored 12-unit gutter inside the device's safe edge.
            let playerSummaryCenterX = max(
                desiredPlayerSummaryCenterX,
                geometry.safeAreaInsets.leading + 262 * scale
            )
            let rankingContentLeftX = dividerScreenX + (735 - authoredDividerX) * scale
            let authoredRankingWidth = (1600 - 735) * scale
            let usesTabletComposition = UIDevice.current.userInterfaceIdiom == .pad
            // The authored 16:9 composition deliberately leaves a closing-page
            // margin. On iPad that margin becomes visually oversized because the
            // artwork is aspect-filled while the foreground stays width-scaled.
            // Let only the scrollable right page use the available tablet width;
            // phones keep their already-calibrated geometry unchanged.
            let rankingContentRightX = usesTabletComposition
                ? geometry.size.width - max(
                    geometry.safeAreaInsets.trailing + 34 * scale,
                    48 * scale
                )
                : rankingContentLeftX + authoredRankingWidth
            let rankingContentWidth = max(authoredRankingWidth, rankingContentRightX - rankingContentLeftX)
            let desiredBackButtonCenterX = dividerScreenX
                - (authoredDividerX - authoredBackButtonCenterX) * scale
            let backButtonCenterX = max(
                desiredBackButtonCenterX,
                geometry.safeAreaInsets.leading + 37 * scale
            )
            // The leaderboard content may be vertically centred on a taller
            // iPad canvas, but navigation belongs to the screen edge. Keeping
            // the back control on the authored top inset matches the iPhone
            // composition and avoids the button drifting toward mid-screen.
            let backButtonCenterY = max(
                geometry.safeAreaInsets.top + 37 * scale,
                78 * scale
            )
            ZStack {
                rankingBackground(size: geometry.size)

                rankingBackButton(scale: scale, action: onClose)
                    .position(
                        x: backButtonCenterX,
                        y: backButtonCenterY
                    )
                    .zIndex(3)

                playerSummary(scale: scale)
                    .frame(width: 500 * scale, height: 754 * scale)
                    .position(
                        x: playerSummaryCenterX,
                        y: artworkOriginY + 426 * scale
                    )

                rankingBoard(
                    scale: scale,
                    headerWidth: authoredRankingWidth
                )
                    .frame(
                        width: max(680 * scale, rankingContentWidth),
                        height: 754 * scale
                    )
                    .position(
                        x: rankingContentLeftX + rankingContentWidth / 2 + 12 * scale,
                        y: artworkOriginY + 426 * scale
                    )
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .task { await service.loadLeaderboard() }
    }

    @ViewBuilder
    private func playerSummary(scale: CGFloat) -> some View {
        if service.profile == nil {
            accountCreationSummary(scale: scale)
        } else {
            registeredPlayerSummary(scale: scale)
        }
    }

    private func registeredPlayerSummary(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 70 * scale)
            Text(L10n.text("ranking.your_profile"))
                .rankingEyebrow(color: GameTheme.cyan, scale: scale)
                .padding(.bottom, 14 * scale)
            if let profile = service.profile {
                RankingIconView(icon: profile.icon, size: 124 * scale)
                Text(profile.displayName)
                    .font(.system(size: 36 * scale, weight: .black, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.60)
                    .padding(.top, 10 * scale)
            }
            HStack(spacing: 10 * scale) {
                personalStat(label: L10n.text("ranking.world_rank"), value: worldRank.map { "#\($0)" } ?? "—", color: GameTheme.gold, scale: scale)
                personalStat(
                    label: L10n.text("ranking.your_best"),
                    value: currentEntry.map { L10n.format("format.seconds_short", $0.survivalTime) } ?? "—",
                    color: GameTheme.cyan,
                    scale: scale
                )
            }
            .padding(.top, 18 * scale)

            Spacer(minLength: 18 * scale)

            Text(L10n.text("ranking.account_note"))
                .font(.system(size: 16 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onPlayRanked) {
                HStack(spacing: 12 * scale) {
                    Image(systemName: "trophy.fill")
                    VStack(alignment: .leading, spacing: 1 * scale) {
                        Text(L10n.text("ranking.play"))
                        Text(
                            rankedRunsRemaining > 0
                                ? L10n.format("ranking.reward.remaining", rankedRunsRemaining)
                                : L10n.text("ranking.reward.ad_required_short")
                        )
                            .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(.black.opacity(0.58))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .rankingPrimaryButton(scale: scale)
            }
            .buttonStyle(RankingPressStyle())
            .padding(.top, 15 * scale)
        }
    }

    private func accountCreationSummary(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 108 * scale)

            Text(L10n.text("ranking.guest_eyebrow"))
                .rankingEyebrow(color: GameTheme.cyan, scale: scale)

            ZStack {
                Circle()
                    .stroke(GameTheme.gold.opacity(0.24), lineWidth: 2 * scale)
                    .frame(width: 154 * scale, height: 154 * scale)
                Circle()
                    .fill(Color(red: 0.03, green: 0.55, blue: 0.64))
                    .frame(width: 124 * scale, height: 124 * scale)
                    .overlay {
                        Circle()
                            .stroke(GameTheme.gold, lineWidth: 5 * scale)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 7 * scale, y: 4 * scale)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 51 * scale, weight: .black))
                    .foregroundStyle(.white)
            }
            .padding(.top, 17 * scale)

            Text(L10n.text("ranking.guest_title"))
                .font(.system(size: 34 * scale, weight: .black, design: .rounded))
                .foregroundStyle(RankingPalette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .padding(.top, 15 * scale)

            Text(L10n.text("ranking.guest_message"))
                .font(.system(size: 18 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.58))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10 * scale)

            Spacer(minLength: 22 * scale)

            Button(action: onCreateAccount) {
                HStack(spacing: 12 * scale) {
                    Image(systemName: "person.badge.plus")
                    Text(L10n.text("ranking.create_account"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .rankingPrimaryButton(scale: scale)
            }
            .buttonStyle(RankingPressStyle())

            Text(L10n.text("ranking.account_note"))
                .font(.system(size: 15 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.54))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14 * scale)
        }
    }

    private func rankingBoard(scale: CGFloat, headerWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(L10n.text("ranking.eyebrow"))
                    .rankingEyebrow(color: GameTheme.coral, scale: scale)
                Text(L10n.text("ranking.title"))
                    .font(.system(size: 52 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(RankingPalette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 3 * scale)
                    .shadow(color: .white.opacity(0.72), radius: 1 * scale, y: -1 * scale)
                    .shadow(color: .black.opacity(0.24), radius: 2.5 * scale, y: 2.5 * scale)

                Label(L10n.text("ranking.rules"), systemImage: "equal.circle.fill")
                    .font(.system(size: 16 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.09, green: 0.30, blue: 0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .padding(.horizontal, 16 * scale)
                    .frame(minHeight: 36 * scale)
                    .background(.white.opacity(0.42), in: Capsule())
                    .overlay(Capsule().stroke(GameTheme.cyan.opacity(0.38), lineWidth: 1.5 * scale))
                    .shadow(color: .black.opacity(0.18), radius: 4 * scale, y: 3 * scale)
                    .padding(.top, 9 * scale)

                HStack(spacing: 10 * scale) {
                    Menu {
                        ForEach(service.availableSeasons) { season in
                            Button {
                                Task { await service.selectSeason(season) }
                            } label: {
                                if season == service.selectedSeason {
                                    Label(season.localizedLabel, systemImage: "checkmark")
                                } else {
                                    Text(season.localizedLabel)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 7 * scale) {
                            Image(systemName: "calendar")
                            Text(service.selectedSeason.localizedLabel)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11 * scale, weight: .black))
                        }
                        .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(RankingPalette.ink)
                        .padding(.horizontal, 14 * scale)
                        .frame(minHeight: 34 * scale)
                        .background(GameTheme.gold.opacity(0.20), in: Capsule())
                        .overlay(Capsule().stroke(GameTheme.gold.opacity(0.65), lineWidth: 1.5 * scale))
                    }

                    if service.isViewingCurrentSeason {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Label(
                                seasonRemainingText(at: context.date),
                                systemImage: "hourglass.bottomhalf.filled"
                            )
                            .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(GameTheme.coral)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 13 * scale)
                            .frame(minHeight: 31 * scale)
                            .background(GameTheme.coral.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(GameTheme.coral.opacity(0.45), lineWidth: 1.25 * scale))
                        }
                    }
                }
                .padding(.top, 8 * scale)

                Label {
                    Text(L10n.text("ranking.season.champion_reward"))
                } icon: {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(GameTheme.coral)
                }
                    .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.05, green: 0.31, blue: 0.36))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
                    .padding(.horizontal, 14 * scale)
                    .padding(.vertical, 7 * scale)
                    .frame(maxWidth: 610 * scale)
                    .background(GameTheme.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 12 * scale))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12 * scale)
                            .stroke(GameTheme.cyan.opacity(0.62), lineWidth: 1.25 * scale)
                    }
                    .padding(.top, 8 * scale)

                accentRule(scale: scale)
                    .padding(.top, 9 * scale)
                    .padding(.bottom, 10 * scale)
            }
            .frame(width: headerWidth)
            // Centre the title against the full Top 100 region. On iPhone the
            // board and authored header widths are identical, so this remains
            // pixel-equivalent to the existing phone composition.
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Text(
                    service.isViewingCurrentSeason
                        ? L10n.text("ranking.top100")
                        : L10n.text("ranking.season.final_standings")
                )
                    .font(.system(size: 16 * scale, weight: .black, design: .rounded))
                    .tracking(2.2 * scale)
                Spacer()
                Label(L10n.text("ranking.scroll_hint"), systemImage: "arrow.up.arrow.down")
                    .padding(.horizontal, 10 * scale)
                    .frame(minHeight: 27 * scale)
                    .background(.white.opacity(0.46), in: Capsule())
            }
            .font(.system(size: 14 * scale, weight: .bold, design: .rounded))
            .foregroundStyle(.black.opacity(0.60))
            .padding(.horizontal, 18 * scale)
            .padding(.bottom, 7 * scale)

            Group {
                if service.isLoadingLeaderboard && service.leaderboard.isEmpty {
                    ProgressView().scaleEffect(1.35).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.leaderboard.isEmpty {
                    ContentUnavailableView(
                        L10n.text("ranking.empty"),
                        systemImage: "trophy",
                        description: Text(L10n.text("ranking.empty_message"))
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 8 * scale) {
                                ForEach(Array(displayedLeaderboard.enumerated()), id: \.element.id) { index, entry in
                                    rankingRow(entry: entry, rank: index + 1, scale: scale)
                                        .id(entry.id)
                                        .scaleEffect(
                                            isAnimatingPersonalBestEntry && entry.id == service.profile?.uid
                                                ? 1.045
                                                : 1
                                        )
                                        .zIndex(entry.id == service.profile?.uid ? 2 : 0)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 7 * scale)
                            .padding(.top, 2 * scale)
                            .padding(.bottom, 18 * scale)
                        }
                        .scrollIndicators(.visible)
                        .contentMargins(.trailing, 5 * scale, for: .scrollIndicators)
                        .task(id: service.leaderboard) {
                            await playPersonalBestPlacementIfNeeded(proxy: proxy)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func playPersonalBestPlacementIfNeeded(proxy: ScrollViewProxy) async {
        let finalLeaderboard = service.leaderboard
        guard presentsPersonalBestPlacement,
              !didPlayPersonalBestPlacement,
              let uid = service.profile?.uid,
              let finalIndex = finalLeaderboard.firstIndex(where: { $0.id == uid }) else {
            displayedLeaderboard = finalLeaderboard
            return
        }

        var previousLeaderboard = finalLeaderboard
        let playerEntry = previousLeaderboard.remove(at: finalIndex)
        if let previousRank = service.previousRankForLatestSubmission {
            let previousIndex = min(max(0, previousRank - 1), previousLeaderboard.count)
            previousLeaderboard.insert(playerEntry, at: previousIndex)
            displayedLeaderboard = previousLeaderboard
            await Task.yield()
            proxy.scrollTo(uid, anchor: .center)
            try? await Task.sleep(for: .milliseconds(550))
        } else {
            // A first-time participant enters just beneath the existing board,
            // then the same row climbs to the newly earned position.
            displayedLeaderboard = previousLeaderboard
            await Task.yield()
            if let lastID = previousLeaderboard.last?.id {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                displayedLeaderboard.append(playerEntry)
            }
            try? await Task.sleep(for: .milliseconds(600))
        }

        isAnimatingPersonalBestEntry = true
        withAnimation(.spring(response: 1.05, dampingFraction: 0.82)) {
            displayedLeaderboard = finalLeaderboard
            proxy.scrollTo(uid, anchor: .center)
        }
        try? await Task.sleep(for: .milliseconds(1_150))
        withAnimation(.easeOut(duration: 0.22)) {
            isAnimatingPersonalBestEntry = false
        }
        didPlayPersonalBestPlacement = true
    }

    private func seasonRemainingText(at date: Date) -> String {
        let remaining = max(0, Int(service.currentSeason.endDate.timeIntervalSince(date)))
        let days = remaining / 86_400
        let hours = remaining % 86_400 / 3_600
        let minutes = remaining % 3_600 / 60
        let seconds = remaining % 60
        if days > 0 {
            return L10n.format("ranking.season.remaining_days", days, hours, minutes)
        }
        return L10n.format("ranking.season.remaining_time", hours, minutes, seconds)
    }

    private func rankingRow(entry: LeaderboardEntry, rank: Int, scale: CGFloat) -> some View {
        HStack(spacing: 13 * scale) {
            Text("\(rank)")
                .font(.system(size: 23 * scale, weight: .black, design: .rounded))
                .foregroundStyle(rank <= 3 ? podiumColor(rank) : .black.opacity(0.64))
                .frame(width: 38 * scale)
            RankingIconView(icon: entry.icon, size: 42 * scale)
            Text(entry.displayName)
                .font(.system(size: 22 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(RankingPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if OfficialRankingAccounts.isSeasonRewardExcluded(uid: entry.id) {
                Text(L10n.text("ranking.season.reward_excluded"))
                    .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.82, green: 0.04, blue: 0.09))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer()
            Text(L10n.format("format.seconds_short", entry.survivalTime))
                .font(.system(size: 24 * scale, weight: .black, design: .rounded))
                .monospacedDigit().foregroundStyle(Color(red: 0.01, green: 0.34, blue: 0.39))
            leaderboardRankBadge(for: entry, scale: scale)
        }
        .padding(.horizontal, 15 * scale)
        .frame(minHeight: (rank <= 3 ? 70 : 58) * scale)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                    .fill(Color(red: 0.22, green: 0.16, blue: 0.09).opacity(0.20))
                    .offset(y: 4 * scale)

                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                    .fill(
                        entry.id == service.profile?.uid
                            ? GameTheme.cyan.opacity(0.19)
                            : .white.opacity(rank == 1 ? 0.58 : 0.36)
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14 * scale)
                .stroke(
                    entry.id == service.profile?.uid
                        ? GameTheme.cyan.opacity(0.52)
                        : (rank <= 3 ? podiumColor(rank).opacity(0.46) : .clear),
                    lineWidth: 1.5 * scale
                )
        }
        .shadow(color: .white.opacity(0.58), radius: 1 * scale, y: -1 * scale)
        .shadow(color: .black.opacity(0.18), radius: 4 * scale, y: 3 * scale)
    }

    private func leaderboardRankBadge(for entry: LeaderboardEntry, scale: CGFloat) -> some View {
        let performanceRank = PerformanceRank(survivalTime: entry.survivalTime)
        let color = leaderboardRankColor(performanceRank)
        return Text(performanceRank.rawValue)
            .font(.system(size: 18 * scale, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .frame(width: 60 * scale, height: 34 * scale)
            .background(color.opacity(0.13), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 1.5 * scale))
    }

    private func leaderboardRankColor(_ rank: PerformanceRank) -> Color {
        switch rank.tier {
        case .sss: Color(red: 0.78, green: 0.05, blue: 0.28)
        case .ss: GameTheme.violet
        case .s: Color(red: 0.64, green: 0.39, blue: 0.02)
        case .a: Color(red: 0.05, green: 0.46, blue: 0.31)
        case .b: Color(red: 0.01, green: 0.34, blue: 0.39)
        case .c: Color(red: 0.70, green: 0.20, blue: 0.15)
        case .d: Color(red: 0.39, green: 0.34, blue: 0.29)
        }
    }

    private func personalStat(label: String, value: String, color: Color, scale: CGFloat) -> some View {
        VStack(spacing: 4 * scale) {
            Text(label).font(.system(size: 15 * scale, weight: .black, design: .rounded)).foregroundStyle(.black.opacity(0.62))
            Text(value)
                .font(.system(size: 26 * scale, weight: .black, design: .rounded))
                .monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, minHeight: 70 * scale)
        .background(.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 15 * scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15 * scale).stroke(color.opacity(0.30), lineWidth: 1.5 * scale) }
    }

    private var currentEntry: LeaderboardEntry? {
        guard let uid = service.profile?.uid else { return nil }
        return service.leaderboard.first { $0.id == uid }
    }

    private var worldRank: Int? {
        guard let uid = service.profile?.uid,
              let index = service.leaderboard.firstIndex(where: { $0.id == uid }) else { return nil }
        return index + 1
    }

    private func podiumColor(_ rank: Int) -> Color {
        switch rank {
        case 1: GameTheme.gold
        case 2: Color(red: 0.46, green: 0.52, blue: 0.55)
        default: Color(red: 0.67, green: 0.37, blue: 0.20)
        }
    }
}

struct RankingIconView: View {
    let icon: ProfileIcon
    let size: CGFloat

    var body: some View {
        Group {
            if let assetName = icon.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.13)
            } else {
                Image(systemName: icon.symbolName)
                    .font(.system(size: size * 0.43, weight: .black))
                    .foregroundStyle(.white)
            }
        }
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [GameTheme.cyan, Color(red: 0.03, green: 0.31, blue: 0.38)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay(Circle().stroke(GameTheme.gold.opacity(0.90), lineWidth: max(2, size * 0.045)))
            .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.05)
    }
}

private struct ProfileIconPickerOverlay: View {
    @Binding var selection: ProfileIcon
    let availableIcons: [ProfileIcon]
    let scale: CGFloat
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 18 * scale) {
                    VStack(alignment: .leading, spacing: 4 * scale) {
                        Text(L10n.text("account.icon_picker_title"))
                            .font(.system(size: 34 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(RankingPalette.ink)
                        Text(L10n.text("account.icon_picker_subtitle"))
                            .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.60))
                    }
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20 * scale, weight: .black))
                            .foregroundStyle(RankingPalette.ink)
                            .frame(width: 46 * scale, height: 46 * scale)
                            .background(.white.opacity(0.48), in: Circle())
                            .overlay(Circle().stroke(.black.opacity(0.18), lineWidth: 1.5 * scale))
                    }
                    .buttonStyle(RankingPressStyle())
                }

                accentRule(scale: scale)
                    .padding(.vertical, 17 * scale)

                LazyVGrid(columns: columns, spacing: 14 * scale) {
                    ForEach(availableIcons) { candidate in
                        Button {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.70)) {
                                selection = candidate
                            }
                        } label: {
                            RankingIconView(icon: candidate, size: 78 * scale)
                                .padding(9 * scale)
                                .frame(maxWidth: .infinity)
                                .background(
                                    selection == candidate ? GameTheme.cyan.opacity(0.15) : .white.opacity(0.32),
                                    in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                                        .stroke(
                                            selection == candidate ? GameTheme.gold : .black.opacity(0.10),
                                            lineWidth: selection == candidate ? 3 * scale : 1.5 * scale
                                        )
                                }
                                .scaleEffect(selection == candidate ? 1.04 : 0.96)
                        }
                        .buttonStyle(RankingPressStyle())
                        .accessibilityLabel(candidate.rawValue)
                        .accessibilityAddTraits(selection == candidate ? .isSelected : [])
                    }
                }

                HStack(spacing: 12 * scale) {
                    Button(action: onCancel) {
                        Text(L10n.text("account.icon_picker_cancel"))
                            .font(.system(size: 19 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(RankingPalette.ink)
                            .frame(width: 160 * scale, height: 58 * scale)
                            .background(.white.opacity(0.40), in: RoundedRectangle(cornerRadius: 16 * scale))
                            .overlay(RoundedRectangle(cornerRadius: 16 * scale).stroke(.black.opacity(0.22), lineWidth: 1.5 * scale))
                    }
                    .buttonStyle(RankingPressStyle())

                    Button(action: onConfirm) {
                        HStack(spacing: 10 * scale) {
                            Image(systemName: "checkmark")
                            Text(L10n.text("account.icon_picker_confirm"))
                        }
                        .font(.system(size: 20 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(RankingPalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 58 * scale)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.84, blue: 0.34), Color(red: 0.93, green: 0.63, blue: 0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16 * scale)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 16 * scale).stroke(.black.opacity(0.56), lineWidth: 2 * scale))
                    }
                    .buttonStyle(RankingPressStyle())
                }
                .padding(.top, 18 * scale)
            }
            .padding(24 * scale)
            .frame(width: 900 * scale)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.98, green: 0.94, blue: 0.84), Color(red: 0.91, green: 0.84, blue: 0.69)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28 * scale, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28 * scale, style: .continuous)
                    .stroke(.black.opacity(0.58), lineWidth: 2.5 * scale)
                    .padding(2 * scale)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 23 * scale, style: .continuous)
                    .stroke(GameTheme.cyan.opacity(0.38), lineWidth: 1.5 * scale)
                    .padding(8 * scale)
            }
            .shadow(color: .black.opacity(0.34), radius: 24 * scale, y: 12 * scale)
        }
    }
}

private enum RankingPalette {
    static let ink = Color(red: 0.11, green: 0.09, blue: 0.06)
}

private func rankingSideInset(_ geometry: GeometryProxy, scale: CGFloat) -> CGFloat {
    UIDevice.current.userInterfaceIdiom == .phone
        ? max(108 * scale, geometry.safeAreaInsets.leading + 16 * scale)
        : max(54 * scale, geometry.safeAreaInsets.leading + 16 * scale)
}

private func rankingBackButton(scale: CGFloat, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "chevron.left")
            .font(.system(size: 28 * scale, weight: .black))
            .foregroundStyle(RankingPalette.ink)
            .frame(width: 58 * scale, height: 58 * scale)
            .background(.white.opacity(0.38), in: Circle())
            .overlay(Circle().stroke(GameTheme.gold.opacity(0.60), lineWidth: 2 * scale))
    }
    .buttonStyle(RankingPressStyle())
}

private func iconEditBadge(scale: CGFloat) -> some View {
    Image(systemName: "pencil")
        .font(.system(size: 16 * scale, weight: .black))
        .foregroundStyle(RankingPalette.ink)
        .frame(width: 38 * scale, height: 38 * scale)
        .background(GameTheme.gold, in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.88), lineWidth: 2 * scale))
        .shadow(color: .black.opacity(0.24), radius: 4 * scale, y: 2 * scale)
}

private func accentRule(scale: CGFloat) -> some View {
    HStack(spacing: 0) {
        Rectangle().fill(GameTheme.cyan).frame(width: 120 * scale, height: 2 * scale)
        Circle().fill(GameTheme.cyan).frame(width: 8 * scale, height: 8 * scale)
        Rectangle().fill(GameTheme.gold.opacity(0.55)).frame(maxWidth: .infinity).frame(height: 1 * scale)
    }
}

private func ledgerDivider(scale: CGFloat) -> some View {
    ZStack {
        Rectangle().fill(GameTheme.gold.opacity(0.42)).frame(width: 1 * scale)
        Circle()
            .fill(Color(red: 0.05, green: 0.37, blue: 0.42))
            .frame(width: 15 * scale, height: 15 * scale)
            .overlay(Circle().stroke(GameTheme.gold, lineWidth: 3 * scale))
    }
    .frame(width: 15 * scale)
}

private func rankingBackground(size: CGSize) -> some View {
    AdaptiveLandscapeArtwork(
        imageName: "result_ledger_opaque_bg",
        viewportSize: size,
        usesTabletComposition: UIDevice.current.userInterfaceIdiom == .pad
    )
    .overlay {
        LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.06)], startPoint: .leading, endPoint: .trailing)
    }
    .allowsHitTesting(false)
}

private func accountBackground(size: CGSize) -> some View {
    AdaptiveLandscapeArtwork(
        imageName: "account_observatory_bg_v2",
        viewportSize: size,
        usesTabletComposition: UIDevice.current.userInterfaceIdiom == .pad
    )
    .overlay {
        LinearGradient(
            colors: [.black.opacity(0.08), .clear, .black.opacity(0.06)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    .allowsHitTesting(false)
}

private struct RankingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private extension Text {
    func rankingEyebrow(color: Color, scale: CGFloat) -> some View {
        font(.system(size: 19 * scale, weight: .black, design: .rounded))
            .tracking(3 * scale)
            .foregroundStyle(color)
    }
}

private extension View {
    func rankingPrimaryButton(scale: CGFloat) -> some View {
        font(.system(size: 27 * scale, weight: .black, design: .rounded))
            .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.035))
            .padding(.horizontal, 28 * scale)
            .frame(maxWidth: .infinity, minHeight: 72 * scale)
            .background(
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.84, blue: 0.34), Color(red: 0.93, green: 0.63, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
                    .stroke(.black.opacity(0.66), lineWidth: 2.5 * scale)
                    .padding(2 * scale)
            }
            .shadow(color: GameTheme.gold.opacity(0.24), radius: 12 * scale, y: 4 * scale)
    }

    func accountSurface(accent: Color, scale: CGFloat) -> some View {
        background(
            Color(red: 0.95, green: 0.90, blue: 0.79).opacity(0.92),
            in: RoundedRectangle(cornerRadius: 25 * scale, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 25 * scale, style: .continuous)
                .stroke(.black.opacity(0.54), lineWidth: max(1.5, 2.5 * scale))
                .padding(2 * scale)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
                .stroke(accent.opacity(0.40), lineWidth: max(1, 1.5 * scale))
                .padding(8 * scale)
        }
        .shadow(color: .black.opacity(0.20), radius: 10 * scale, y: 6 * scale)
    }

    func accountInnerSurface(scale: CGFloat) -> some View {
        background(.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 17 * scale))
            .overlay {
                RoundedRectangle(cornerRadius: 17 * scale)
                    .stroke(GameTheme.gold.opacity(0.22), lineWidth: 1.5 * scale)
            }
    }
}
