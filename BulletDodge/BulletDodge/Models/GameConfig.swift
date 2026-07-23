import CoreGraphics
import Foundation

enum GameConfig {
    static let referenceScale: CGFloat = 5.0 / 5.5
    static let movementReferenceTileSize: CGFloat = 33.6
    static let autoWallTestEnabled = ProcessInfo.processInfo.environment["BULLETDODGE_AUTO_WALL_TEST"] == "1"
    static let autoAttackTestEnabled = ProcessInfo.processInfo.environment["BULLETDODGE_AUTO_ATTACK_TEST"] == "1"
    static let debugProjectileLoggingEnabled = ProcessInfo.processInfo.environment["BULLETDODGE_DEBUG_PROJECTILES"] == "1"
    static let debugProjectileTargetOffsetX: CGFloat = CGFloat(Double(ProcessInfo.processInfo.environment["BULLETDODGE_DEBUG_PROJECTILE_OFFSET_X"] ?? "0") ?? 0)
    static let debugProjectileTargetOffsetY: CGFloat = CGFloat(Double(ProcessInfo.processInfo.environment["BULLETDODGE_DEBUG_PROJECTILE_OFFSET_Y"] ?? "0") ?? 0)
    static let debugHideActorsEnabled = ProcessInfo.processInfo.environment["BULLETDODGE_HIDE_ACTORS"] == "1"
    static let debugCornerAttackTestEnabled = ProcessInfo.processInfo.environment["BULLETDODGE_CORNER_ATTACK_TEST"] == "1"
    static let debugCornerStartPosition = ProcessInfo.processInfo.environment["BULLETDODGE_CORNER_START"] ?? "bottom-left"
    static let debugCornerDamageEnabled = ProcessInfo.processInfo.environment["BULLETDODGE_CORNER_DAMAGE"] == "1"
    static let autoWallTestSpeedMultiplier: CGFloat = autoWallTestEnabled ? 2.6 : 1.0
    static let enemyMovementEnabled = true
    static let enemyAttacksEnabled = true

    static let tileSize: CGFloat = movementReferenceTileSize * referenceScale
    static let mapColumns: CGFloat = 21
    static let mapRows: CGFloat = 33
    static let mapSize = CGSize(width: tileSize * mapColumns, height: tileSize * mapRows)
    static let stageSideInset: CGFloat = tileSize * 4.423300970873787
    static let stageTopInset: CGFloat = tileSize * 3.1
    static let stageBottomInset: CGFloat = tileSize * 7.3
    static let stageVisualSize = CGSize(
        width: mapSize.width + stageSideInset * 2,
        height: mapSize.height + stageTopInset + stageBottomInset
    )
    // The 2622-pixel-wide, 460-ppi reference screen measures 14.478 cm.
    // With the existing camera scale, 0.414042 tiles per side produces the
    // measured 10.3 cm near-wall playable width without changing movement
    // speed or the amount of map visible on screen.
    static let playableSideInset: CGFloat = tileSize * 0.4140419947506581
    static let playableLeftInset: CGFloat = playableSideInset
    static let playableRightInset: CGFloat = playableSideInset
    static let playableTopInset: CGFloat = 0
    static let playableBottomExtension: CGFloat = 0
    // On the reference device the playable width measures 10.3 cm at the
    // near wall and 9.5 cm at the far wall. SpriteKit is a flat projection, so
    // reproduce that 7.77% screen-space narrowing with a centered trapezoid.
    static let playableNearWidth: CGFloat = mapSize.width
        - playableLeftInset
        - playableRightInset
    static let playableUpperWallInset: CGFloat = playableNearWidth * (1 - 9.5 / 10.3) / 2
    static let playableUpperLeftWallInset: CGFloat = playableUpperWallInset
    static let playableUpperRightWallInset: CGFloat = playableUpperWallInset
    static let cameraVisibleWidth: CGFloat = stageVisualSize.width * 0.95
    static let cameraVisibleHeight: CGFloat = tileSize * 15.9
    static let cameraTilesVisibleAbovePlayer: CGFloat = 8.0
    static let cameraTilesVisibleAbovePlayerAtBottom: CGFloat = 8.0
    static let cameraBottomBlendDistanceTiles: CGFloat = 8.0
    static let cameraHorizontalLeadFactor: CGFloat = 0.0

    // Only the measured outer dimensions come from the reference footage.
    // Artwork, colors and internal construction remain original to this app.
    static let referenceBattlePixelSize = CGSize(width: 2622, height: 1206)
    static let referencePixelsPerWorldX: CGFloat = referenceBattlePixelSize.width
        / cameraVisibleWidth
    static let referencePixelsPerWorldY: CGFloat = referenceBattlePixelSize.height
        / cameraVisibleHeight
    // Stroke and glow extend past the vector path. These calibrated path sizes
    // render to an outer 144 x 112 pixel silhouette on the reference screen.
    static let playerGroundIndicatorSize = CGSize(
        width: 135 / referencePixelsPerWorldX,
        height: 108.5 / referencePixelsPerWorldY
    )
    static let playerGroundIndicatorYOffset: CGFloat = -28
    // Keep the measured width while using a slightly slimmer, softer capsule.
    static let playerHealthBarSize = CGSize(
        width: 121 / referencePixelsPerWorldX,
        height: 28 / referencePixelsPerWorldY
    )
    static let playerHealthBarFillSize = CGSize(
        width: 110 / referencePixelsPerWorldX,
        height: 18 / referencePixelsPerWorldY
    )
    static let playerHealthBarYOffset: CGFloat = playerGroundIndicatorYOffset
        + 140 / referencePixelsPerWorldY

    // A full near-wall traverse originally measured 8.3 s in the app and 8.0 s
    // in the reference. The later matched handling captures provide the more
    // reliable steady-state comparison: the app covered 230-240 px/s while the
    // reference covered 207-216 px/s. Retain the traverse calibration, then
    // apply the measured 0.90 correction for the final reference speed.
    static let playerTraverseSpeedCorrection: CGFloat = (8.3 - 1.0 / 24.0)
        / (8.0 - 1.0 / 24.0)
    static let playerMeasuredSpeedCorrection: CGFloat = 0.90
    static let playerSpeed: CGFloat = movementReferenceTileSize
        * (13 / 4.5)
        * (6.2 / 7.8)
        * (16.8 / 15.7)
        * (7.3 / 8.0)
        * playerTraverseSpeedCorrection
        * playerMeasuredSpeedCorrection
        * autoWallTestSpeedMultiplier
    // The matched 180-degree captures reach zero in roughly 6-8 frames and
    // settle at full opposite speed in 12-15 frames. A 9x linear acceleration
    // gives 0.111 s to zero and 0.222 s for the complete reversal.
    static let playerMovementAcceleration: CGFloat = playerSpeed * 9
    // Ordinary 90-degree turns settle 2-3 frames later than the previous
    // 0.11-second response. This changes velocity response without adding touch
    // latency.
    static let playerSteeringResponseTime: TimeInterval = 0.14
    // Releasing the stick is not an instantaneous stop in the reference. Full
    // speed decays linearly to rest in about nine 60-Hz frames.
    static let playerReleaseTime: TimeInterval = 0.15
    static let playerReleaseDeceleration: CGFloat =
        playerSpeed / CGFloat(playerReleaseTime)
    static let playerHardTurnThreshold: CGFloat = .pi * (5.0 / 6.0)
    static let playerFacingTurnRate: CGFloat = .pi / 0.10
    static let playerMaxHP: CGFloat = 100
    static let playerCollisionRadius: CGFloat = 21
    // Brawl-style damage collision is a direction-independent circle on the
    // ground plane, centered at the character's foot marker rather than the
    // rendered body. The reference footage gives a 5.8 mm central estimate
    // for its horizontal screen diameter.
    static let referencePixelsPerMillimeter: CGFloat = 460 / 25.4
    static let playerHitDiameterMillimeters: CGFloat = 5.8
    static let playerHitRadius: CGFloat = (playerHitDiameterMillimeters
        * referencePixelsPerMillimeter / referencePixelsPerWorldX) / 2
    static let playerHitRadiusX: CGFloat = playerHitRadius
    static let playerHitRadiusY: CGFloat = playerHitRadius
    static let playerHitCenterYOffset: CGFloat = playerGroundIndicatorYOffset
    // Projectile contact is evaluated against this filled ground circle.
    // Rendered body depth, facing direction and visible-art overlap are not
    // part of damage collision.
    static let characterModelDisplayTileMultiplier: CGFloat = ((((116 / 33.6) * 1.08) * 0.68) * 1.25) * 1.5
    static let playerModelDisplayTileMultiplier: CGFloat = characterModelDisplayTileMultiplier * 1.2
    static let enemyModelDisplayTileMultiplier: CGFloat = (characterModelDisplayTileMultiplier * 0.6) * 1.25
    // Visible body target: 4.5 mm wide and 6.0 mm tall, excluding the shadow,
    // ground marker and health bar.
    static let playerModelWidthScale: CGFloat = 1.25 * (4.5 / 5.63)
    static let playerModelHeightScale: CGFloat = 0.608 * 0.75 * (6.0 / 6.5)
    static let enemyModelHeightScale: CGFloat = 0.608 * 0.96
    static let playerVisualRadius: CGFloat = tileSize * 0.5
    static let playerModelDisplaySize = CGSize(
        width: tileSize * playerModelDisplayTileMultiplier,
        height: tileSize * playerModelDisplayTileMultiplier
    )
    static let playerModelViewportSize = CGSize(width: 384, height: 384)
    static let playerHitMaskMaxSize = CGSize(
        width: playerModelDisplaySize.width * playerModelWidthScale,
        height: playerModelDisplaySize.height * playerModelHeightScale
    )
    static let enemyModelDisplaySize = CGSize(
        width: tileSize * enemyModelDisplayTileMultiplier,
        height: tileSize * enemyModelDisplayTileMultiplier
    )

    // Enemy locomotion uses the same maximum ground speed as the player.
    // Returning from off-screen, approaching and retreating never override it.
    static let enemySpeed: CGFloat = playerSpeed
    static let enemyCollisionRadius: CGFloat = 19
    static let enemyVisualRadius: CGFloat = tileSize * 0.5
    static let preferredEnemyDistance: CGFloat = 133
    static let enemyDistanceTolerance: CGFloat = 20
    static let enemyDecisionDurationRange: ClosedRange<TimeInterval> = 2.4...4.2
    static let enemySpawnDistance: CGFloat = 154
    static let enemyAnchorHorizontalOffsetRatio: CGFloat = 0.0
    static let enemyAnchorVerticalOffsetRatio: CGFloat = 0.36
    static let enemyMinVerticalOffsetRatio: CGFloat = 0.18
    static let enemyMaxVerticalOffsetRatio: CGFloat = 0.43
    static let enemyHorizontalLeashRatio: CGFloat = 0.42
    static let enemyHorizontalDriftRangeRatio: CGFloat = 0.22
    static let enemyVerticalDriftRange: ClosedRange<CGFloat> = (-tileSize * 0.6)...(tileSize * 1.0)
    static let enemyBiasSmoothingRate: CGFloat = 1.45
    static let enemySteeringResponse: CGFloat = 3.2
    static let enemyFacingTurnRate: CGFloat = 7.5
    static let enemySlowdownDistance: CGFloat = tileSize * 1.35
    static let enemyMinimumPlayerDistance: CGFloat = tileSize * 2.85
    static let enemyApproachChance: CGFloat = 0.18
    static let enemyApproachDistance: CGFloat = tileSize * 3.25
    static let enemyApproachFireDistance: CGFloat = tileSize * 3.75
    static let enemyApproachAttackDelayRange: ClosedRange<TimeInterval> = 0.35...0.70
    static let enemyRetreatTargetDistance: CGFloat = tileSize * 6.2
    static let enemyRetreatCompletionDistance: CGFloat = tileSize * 5.4
    static let enemyScreenEdgeInset: CGFloat = tileSize * 0.9
    static let enemyWallRecoveryTriggerDistance: CGFloat = tileSize * 2.2
    static let enemyWallRecoveryReleaseDistance: CGFloat = tileSize * 4.6
    static let enemyWallRecoveryArrivalDistance: CGFloat = tileSize * 0.35
    static let enemyWallRecoveryArrivalAttackDelay: TimeInterval = 0.65
    static let enemyWallRecoveryAttackIntervalRange: ClosedRange<TimeInterval> = 1.4...2.4
    static let enemyBobAmplitude: CGFloat = 3
    static let enemyBobSpeed: CGFloat = 0.72
    static let enemyReferenceFollowRate: CGFloat = 1.15

    static let joystickLeftInset: CGFloat = 112
    static let joystickBottomInset: CGFloat = 104

    // 60 fps reference timing: the throw pose begins 10-11 frames before the
    // projectile separates, then settles back to idle within roughly 29 frames.
    static let enemyThrowDuration: TimeInterval = 0.48
    static let enemyThrowReleaseTime: TimeInterval = 0.18
    static let enemyInitialAttackDelayRange: ClosedRange<TimeInterval> = 1.8...3.2
    static let enemyAttackIntervalRange: ClosedRange<TimeInterval> = 0.9...3.0
    static let enemyBurstShotDelayRange: ClosedRange<TimeInterval> = 0.30...0.48
    static let enemySingleShotWeight = 52
    static let enemyDoubleShotWeight = 33
    static let enemyTripleShotWeight = 15
    static let enemySmallAimOffsetRange: ClosedRange<CGFloat> = (tileSize * 0.65)...(tileSize * 1.25)
    static let enemyLargeAimOffsetRange: ClosedRange<CGFloat> = (tileSize * 1.75)...(tileSize * 2.75)
    static let autoAttackInitialFireDelay: TimeInterval = 1.60
    static let autoAttackRepeatFireDelay: TimeInterval = 99.0
    // Brawl Stars reference: the parent projectile travels 2.6 cm in 1.1 seconds.
    // The target device renders at 460 native pixels per inch and 3 pixels per point.
    static let targetNativePixelsPerInch: CGFloat = 460
    static let targetNativePixelsPerPoint: CGFloat = 3
    static let targetPointsPerMillimeter: CGFloat = targetNativePixelsPerInch
        / targetNativePixelsPerPoint
        / 25.4
    static let thornBallTravelCentimeters: CGFloat = 2.6
    static let thornBallVisualDiameter: CGFloat = 4.8 * targetPointsPerMillimeter
    static let thornBallLifetime: TimeInterval = 1.1
    static let thornBallRange: CGFloat = thornBallTravelCentimeters
        * (targetNativePixelsPerInch / targetNativePixelsPerPoint)
        / 2.54
    static let thornBallSpeed: CGFloat = thornBallRange / CGFloat(thornBallLifetime)
    static let thornBallDamage: CGFloat = 12
    static let thornBallRadius: CGFloat = 22
    static let thornBallContactRadius: CGFloat = thornBallVisualDiameter * 0.5
    static let thornBallSpawnInset: CGFloat = 12
    static let thornBallTargetLeadFactor: CGFloat = 0.14
    static let explosionRadius: CGFloat = 20
    static let explosionDamage: CGFloat = 15
    static let thornShardCount = 6
    static let thornShardSpeed: CGFloat = 540
    static let thornShardRange: CGFloat = 1700
    static let thornShardDamage: CGFloat = 10
    static let thornShardRadius: CGFloat = 24
    static let thornShardVisualWidth: CGFloat = 2.5 * targetPointsPerMillimeter
    // The latest side-by-side ruler check shows the reference thorn is just under
    // 1.5 mm while the previous render was nearly 2 mm long. Preserve its width
    // and shorten only the direction-aligned axis by the measured ~0.72 ratio.
    static let thornShardVisualLength: CGFloat = 2.9 * targetPointsPerMillimeter
    // The six reference boundary captures constrain the shard collision core
    // to roughly 1.25 mm. It is a ground-plane circle around the shard shadow,
    // not a percentage of the visible triangular artwork.
    static let thornShardContactRadius: CGFloat = 1.25 * targetPointsPerMillimeter
    static let thornShardCurveDelay: TimeInterval = 0.0
    static let thornShardAngularVelocity: CGFloat = 0.08
    static let thornShardCollisionDelay: TimeInterval = 0.07
    static let thornShardSpawnOffset: CGFloat = 18
    static let thornShardFlightDuration: TimeInterval = 0.62
    // A forward-curving thorn crosses the parent projectile's aim line at
    // roughly this radius. Edge pressure should use this standoff distance so
    // the thorn can connect without forcing a main-ball contact.
    static let thornShardForwardCrossingDistance: CGFloat = 84
    static let enemyThornAttackPositionDistance: CGFloat = enemyVisualRadius
        + thornBallSpawnInset
        + thornBallRange
        + thornShardForwardCrossingDistance
    static let enemyThornAttackDistanceTolerance: CGFloat = tileSize * 0.45

    static let maxAmmo = 3
    static let reloadInterval: TimeInterval = 1.0
    static let shakeDuration: TimeInterval = 0.18
    static let shakeAmplitude: CGFloat = 10
}
