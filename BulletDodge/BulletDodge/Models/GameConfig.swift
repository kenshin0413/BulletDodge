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
    static let autoWallTestSpeedMultiplier: CGFloat = autoWallTestEnabled ? 2.6 : 1.0
    static let enemyMovementEnabled = false
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
    static let playableLeftInset: CGFloat = 0
    static let playableRightInset: CGFloat = 0
    static let playableTopInset: CGFloat = 0
    static let playableBottomExtension: CGFloat = 0
    static let playableUpperLeftWallInset: CGFloat = 0
    static let playableUpperRightWallInset: CGFloat = 0
    static let cameraVisibleWidth: CGFloat = stageVisualSize.width * 0.95
    static let cameraVisibleHeight: CGFloat = tileSize * 15.9
    static let cameraTilesVisibleAbovePlayer: CGFloat = 8.0
    static let cameraTilesVisibleAbovePlayerAtBottom: CGFloat = 8.0
    static let cameraBottomBlendDistanceTiles: CGFloat = 8.0
    static let cameraHorizontalLeadFactor: CGFloat = 0.0

    static let playerSpeed: CGFloat = movementReferenceTileSize * (13 / 4.5) * (6.2 / 7.8) * (16.8 / 15.7) * (7.3 / 8.0) * autoWallTestSpeedMultiplier
    static let playerMaxHP: CGFloat = 100
    static let playerCollisionRadius: CGFloat = 21
    static let playerHitRadiusX: CGFloat = 18
    static let playerHitRadiusY: CGFloat = 27
    // Gameplay contact follows the character's vulnerable core rather than the
    // full ear/arm/foot silhouette. The rendered alpha mask is contracted by
    // these factors around its center before projectile overlap is tested.
    static let playerHitMaskWidthScale: CGFloat = 0.55
    static let playerHitMaskHeightScale: CGFloat = 0.68
    static let projectileRequiredPlayerOverlap: CGFloat = 0.50
    static let characterModelDisplayTileMultiplier: CGFloat = ((((116 / 33.6) * 1.08) * 0.68) * 1.25) * 1.5
    static let playerModelDisplayTileMultiplier: CGFloat = characterModelDisplayTileMultiplier * 1.2
    static let enemyModelDisplayTileMultiplier: CGFloat = (characterModelDisplayTileMultiplier * 0.6) * 1.25
    static let playerModelWidthScale: CGFloat = 1.25
    static let playerModelHeightScale: CGFloat = 0.608 * 0.75
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

    static let enemySpeed: CGFloat = playerSpeed * (94 / 220)
    static let enemyCollisionRadius: CGFloat = 19
    static let enemyVisualRadius: CGFloat = tileSize * 0.5
    static let preferredEnemyDistance: CGFloat = 133
    static let enemyDistanceTolerance: CGFloat = 20
    static let enemyDecisionDurationRange: ClosedRange<TimeInterval> = 1.2...1.9
    static let enemySpawnDistance: CGFloat = 154
    static let enemyAnchorHorizontalOffsetRatio: CGFloat = 0.0
    static let enemyAnchorVerticalOffsetRatio: CGFloat = 0.42
    static let enemyMinVerticalOffsetRatio: CGFloat = 0.24
    static let enemyMaxVerticalOffsetRatio: CGFloat = 0.64
    static let enemyHorizontalLeashRatio: CGFloat = 0.42
    static let enemyHorizontalDriftRangeRatio: CGFloat = 0.28
    static let enemyVerticalDrift: CGFloat = 45
    static let enemyAnchorFollowStrength: CGFloat = 2.0
    static let enemyBobAmplitude: CGFloat = 13
    static let enemyBobSpeed: CGFloat = 1.25
    static let enemyReferenceFollowRate: CGFloat = 0.16

    static let joystickLeftInset: CGFloat = 112
    static let joystickBottomInset: CGFloat = 104

    static let enemyThrowDuration: TimeInterval = 0.48
    static let enemyThrowReleaseTime: TimeInterval = 0.18
    static let enemyInitialAttackDelayRange: ClosedRange<TimeInterval> = 1.8...3.2
    static let enemyAttackIntervalRange: ClosedRange<TimeInterval> = 0.9...3.0
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
    static let thornBallVisualDiameter: CGFloat = 5.0 * targetPointsPerMillimeter
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
    static let thornShardContactRadius: CGFloat = thornShardVisualWidth * 0.5
    static let thornShardCurveDelay: TimeInterval = 0.0
    static let thornShardAngularVelocity: CGFloat = 0.08
    static let thornShardCollisionDelay: TimeInterval = 0.07
    static let thornShardSpawnOffset: CGFloat = 18
    static let thornShardFlightDuration: TimeInterval = 0.62

    static let maxAmmo = 3
    static let reloadInterval: TimeInterval = 1.0
    static let shakeDuration: TimeInterval = 0.18
    static let shakeAmplitude: CGFloat = 10
}
