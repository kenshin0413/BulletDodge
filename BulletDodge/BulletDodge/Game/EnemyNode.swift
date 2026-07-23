import SceneKit
import SpriteKit

final class EnemyNode: SKNode {
    private enum MovementMode {
        case orbiting
        case approaching
        case retreating
    }

    enum AimStyle: CaseIterable {
        case direct
        case smallOffset
        case largeOffset
    }

    struct ShotContext {
        let burstIndex: Int
        let burstCount: Int
        let aimStyle: AimStyle
    }

    enum AttackUpdateResult {
        case none
        case beganThrow(ShotContext)
        case releaseProjectile(ShotContext)
    }

    private let shadowNode = SKShapeNode(
        ellipseOf: CGSize(
            width: GameConfig.tileSize * 0.74,
            height: GameConfig.tileSize * 0.32
        )
    )
    private let groundIndicatorNode = SKNode()
    private let modelNode = SK3DNode(viewportSize: GameConfig.playerModelViewportSize)
    private let rig = EnemyFigureRig()

    private(set) var ammo = GameConfig.maxAmmo

    private var decisionTimer: TimeInterval = 0
    private var decisionDuration: TimeInterval = 0
    private var reloadTimer: TimeInterval = 0
    private var nextFireTimer: TimeInterval = 0
    private var throwReleaseTimer: TimeInterval = 0
    private var isThrowQueued = false
    private var burstShotsRemaining = 0
    private var activeBurstSize = 0
    private var activeBurstShotIndex = 0
    private var activeAimStyles: [AimStyle] = []
    private var queuedShotContext: ShotContext?
    private var lateralBias: CGFloat = 0
    private var verticalBias: CGFloat = 0
    private var targetLateralBias: CGFloat = 0
    private var targetVerticalBias: CGFloat = 0
    private var movementVelocity: CGVector = .zero
    private var movementMode: MovementMode = .orbiting
    private var currentPlayerDistance: CGFloat = .greatestFiniteMagnitude
    private var isWallRecoveryActive = false
    private var isArenaEdgePressureActive = false
    private var hasReachedWallRecoveryPosition = false
    private var bobTimer: TimeInterval = 0
    private var lastDelta: CGVector = .zero
    private var facingAngle: CGFloat = 0
    private var attackFacingLockTimer: TimeInterval = 0

    override init() {
        super.init()

        configureGroundIndicator()

        shadowNode.position = CGPoint(x: 0, y: -24)
        shadowNode.fillColor = UIColor.black.withAlphaComponent(0.18)
        shadowNode.strokeColor = .clear
        shadowNode.zPosition = -1

        modelNode.scnScene = rig.scene
        modelNode.pointOfView = rig.cameraNode
        let displayScale = GameConfig.enemyModelDisplaySize.width / GameConfig.playerModelViewportSize.width
        modelNode.xScale = displayScale
        modelNode.yScale = displayScale * GameConfig.enemyModelHeightScale
        modelNode.position = CGPoint(x: 0, y: -5)

        addChild(groundIndicatorNode)
        addChild(shadowNode)
        addChild(modelNode)

        chooseNewBias()
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    private func configureGroundIndicator() {
        let size = GameConfig.playerGroundIndicatorSize

        let outer = SKShapeNode(ellipseOf: size)
        outer.fillColor = UIColor(red: 0.12, green: 0.055, blue: 0.24, alpha: 0.34)
        outer.strokeColor = UIColor(red: 0.67, green: 0.34, blue: 1.00, alpha: 0.94)
        outer.lineWidth = 2.4
        outer.glowWidth = 1.2

        let inner = SKShapeNode(
            ellipseOf: CGSize(width: size.width * 0.72, height: size.height * 0.68)
        )
        inner.fillColor = .clear
        inner.strokeColor = UIColor(red: 0.96, green: 0.76, blue: 0.30, alpha: 0.78)
        inner.lineWidth = 1.35

        groundIndicatorNode.position = CGPoint(x: 0, y: -24)
        groundIndicatorNode.zPosition = -2
        groundIndicatorNode.addChild(outer)
        groundIndicatorNode.addChild(inner)
    }

    func reset() {
        ammo = GameConfig.maxAmmo
        decisionTimer = 0
        reloadTimer = 0
        nextFireTimer = GameConfig.autoAttackTestEnabled
            ? GameConfig.autoAttackInitialFireDelay
            : TimeInterval.random(in: GameConfig.enemyInitialAttackDelayRange)
        throwReleaseTimer = 0
        isThrowQueued = false
        burstShotsRemaining = 0
        activeBurstSize = 0
        activeBurstShotIndex = 0
        activeAimStyles.removeAll(keepingCapacity: true)
        queuedShotContext = nil
        bobTimer = 0
        lateralBias = 0
        verticalBias = 0
        targetLateralBias = 0
        targetVerticalBias = 0
        movementVelocity = .zero
        movementMode = .orbiting
        currentPlayerDistance = .greatestFiniteMagnitude
        isWallRecoveryActive = false
        isArenaEdgePressureActive = false
        hasReachedWallRecoveryPosition = false
        lastDelta = .zero
        facingAngle = 0
        attackFacingLockTimer = 0
        rig.resetPose()
        updateDirectionalHeight()
        chooseNewBias()
    }

    func updateMovement(
        deltaTime: TimeInterval,
        desiredAnchor: CGPoint,
        playerPosition: CGPoint,
        mapRect: CGRect,
        visibleRect: CGRect
    ) {
        decisionTimer += deltaTime
        bobTimer += deltaTime
        attackFacingLockTimer = max(0, attackFacingLockTimer - deltaTime)
        if decisionTimer >= decisionDuration {
            chooseBias()
        }

        let biasBlend = min(1, CGFloat(deltaTime) * GameConfig.enemyBiasSmoothingRate)
        lateralBias += (targetLateralBias - lateralBias) * biasBlend
        verticalBias += (targetVerticalBias - verticalBias) * biasBlend

        let bobOffset = sin(bobTimer * GameConfig.enemyBobSpeed) * GameConfig.enemyBobAmplitude
        var targetPoint = CGPoint(
            x: desiredAnchor.x + lateralBias,
            y: desiredAnchor.y + verticalBias + bobOffset
        )

        let fromPlayer = CGVector(
            dx: position.x - playerPosition.x,
            dy: position.y - playerPosition.y
        )
        currentPlayerDistance = fromPlayer.length
        if movementMode == .retreating,
           currentPlayerDistance >= GameConfig.enemyRetreatCompletionDistance {
            finishRetreat()
        }

        switch movementMode {
        case .orbiting:
            break
        case .approaching:
            let approachSideOffset = max(
                -GameConfig.tileSize * 0.8,
                min(GameConfig.tileSize * 0.8, lateralBias * 0.18)
            )
            targetPoint = CGPoint(
                x: playerPosition.x + approachSideOffset,
                y: playerPosition.y + GameConfig.enemyApproachDistance
            )
        case .retreating:
            let retreatDirection = fromPlayer.length > 0
                ? fromPlayer.normalized
                : CGVector(dx: 0, dy: 1)
            targetPoint = CGPoint(
                x: playerPosition.x + retreatDirection.dx * GameConfig.enemyRetreatTargetDistance,
                y: playerPosition.y + retreatDirection.dy * GameConfig.enemyRetreatTargetDistance
            )
        }

        let targetFromPlayer = CGVector(
            dx: targetPoint.x - playerPosition.x,
            dy: targetPoint.y - playerPosition.y
        )
        if targetFromPlayer.length < GameConfig.enemyMinimumPlayerDistance {
            let separationDirection = targetFromPlayer.length > 0
                ? targetFromPlayer.normalized
                : CGVector(dx: 0, dy: 1)
            targetPoint = CGPoint(
                x: playerPosition.x + separationDirection.dx * GameConfig.enemyMinimumPlayerDistance,
                y: playerPosition.y + separationDirection.dy * GameConfig.enemyMinimumPlayerDistance
            )
        }

        let mapSafeRect = mapRect.insetBy(
            dx: GameConfig.enemyCollisionRadius,
            dy: GameConfig.enemyCollisionRadius
        )
        let visibleSafeRect = visibleRect
            .insetBy(dx: GameConfig.enemyScreenEdgeInset, dy: GameConfig.enemyScreenEdgeInset)
            .intersection(mapSafeRect)
        let edgeTriggerDistance = GameConfig.enemyWallRecoveryTriggerDistance
        isArenaEdgePressureActive = playerPosition.x - mapSafeRect.minX <= edgeTriggerDistance
            || mapSafeRect.maxX - playerPosition.x <= edgeTriggerDistance
            || playerPosition.y - mapSafeRect.minY <= edgeTriggerDistance
            || mapSafeRect.maxY - playerPosition.y <= edgeTriggerDistance
        let isOutsideScreen = !visibleSafeRect.isNull
            && !visibleSafeRect.isEmpty
            && !visibleSafeRect.contains(position)
        if isWallRecoveryActive || isArenaEdgePressureActive {
            // At any arena edge, choose a valid point toward the arena
            // interior. Clamping an outward target to the map boundary made
            // the enemy walk against an invisible wall forever at the top.
            let towardArenaInterior = CGVector(
                dx: mapSafeRect.midX - playerPosition.x,
                dy: mapSafeRect.midY - playerPosition.y
            ).normalized
            targetPoint = CGPoint(
                x: playerPosition.x
                    + towardArenaInterior.dx * GameConfig.enemyThornAttackPositionDistance,
                y: playerPosition.y
                    + towardArenaInterior.dy * GameConfig.enemyThornAttackPositionDistance
            ).clamped(in: mapSafeRect)
            if isWallRecoveryActive {
                let recoveryDistance = CGPoint.distance(from: position, to: targetPoint)
                if !hasReachedWallRecoveryPosition,
                   recoveryDistance <= GameConfig.enemyWallRecoveryArrivalDistance {
                    hasReachedWallRecoveryPosition = true
                    nextFireTimer = max(
                        nextFireTimer,
                        GameConfig.enemyWallRecoveryArrivalAttackDelay
                    )
                }
            }
        } else if isOutsideScreen {
            let edgePoint = position.clamped(in: visibleSafeRect)
            targetPoint = CGPoint(
                x: edgePoint.x + (visibleSafeRect.midX - edgePoint.x) * 0.18,
                y: edgePoint.y + (visibleSafeRect.midY - edgePoint.y) * 0.18
            )
        }

        // If the player moved farther away than the fixed parent flight plus
        // its curved thorn can cover, close the gap at normal player speed.
        // Projectile range and fuse remain unchanged.
        if !isArenaEdgePressureActive,
           currentPlayerDistance > GameConfig.enemyThornAttackPositionDistance
                + GameConfig.enemyThornAttackDistanceTolerance {
            let attackDirection = fromPlayer.normalized
            targetPoint = CGPoint(
                x: playerPosition.x
                    + attackDirection.dx * GameConfig.enemyThornAttackPositionDistance,
                y: playerPosition.y
                    + attackDirection.dy * GameConfig.enemyThornAttackPositionDistance
            ).clamped(in: mapSafeRect)
        }

        let toTarget = CGVector(dx: targetPoint.x - position.x, dy: targetPoint.y - position.y)
        let distance = toTarget.length
        // Keep every movement state at the player's ground speed. In
        // particular, leaving the camera no longer triggers a catch-up boost;
        // the enemy is allowed to remain off-screen while it walks back in.
        let followSpeed = GameConfig.enemySpeed
        let slowdown = min(1, distance / max(1, GameConfig.enemySlowdownDistance))
        let desiredVelocity = distance > 0
            ? toTarget.normalized * (followSpeed * slowdown)
            : .zero
        let steeringBlend = min(1, CGFloat(deltaTime) * GameConfig.enemySteeringResponse)
        movementVelocity = CGVector(
            dx: movementVelocity.dx + (desiredVelocity.dx - movementVelocity.dx) * steeringBlend,
            dy: movementVelocity.dy + (desiredVelocity.dy - movementVelocity.dy) * steeringBlend
        )
        let proposedDelta = movementVelocity * CGFloat(deltaTime)
        let delta = proposedDelta.length > distance && distance > 0
            ? toTarget
            : proposedDelta
        let nextPosition = CGPoint(x: position.x + delta.dx, y: position.y + delta.dy)
        position = nextPosition.clamped(in: mapSafeRect)

        lastDelta = deltaTime > 0 ? CGVector(dx: delta.dx / CGFloat(deltaTime), dy: delta.dy / CGFloat(deltaTime)) : .zero
        if attackFacingLockTimer <= 0, lastDelta.length > 2 {
            let desiredFacingAngle = atan2(lastDelta.dx, -lastDelta.dy)
            facingAngle = rotatedAngle(
                from: facingAngle,
                toward: desiredFacingAngle,
                maxStep: GameConfig.enemyFacingTurnRate * CGFloat(deltaTime)
            )
        }
        let movementStrength = min(1, lastDelta.length / max(1, GameConfig.enemySpeed))
        rig.update(
            deltaTime: deltaTime,
            facingAngle: facingAngle,
            movementStrength: movementStrength
        )
        updateDirectionalHeight()
        shadowNode.xScale = 1 - movementStrength * 0.06
        shadowNode.yScale = 1 - movementStrength * 0.10
    }

    func faceAttack(toward targetPoint: CGPoint) {
        let attackDirection = CGVector(
            dx: targetPoint.x - position.x,
            dy: targetPoint.y - position.y
        )
        guard attackDirection.length > 0 else { return }
        facingAngle = atan2(attackDirection.dx, -attackDirection.dy)
        attackFacingLockTimer = GameConfig.enemyThrowDuration
        rig.setFacingAngle(facingAngle)
        updateDirectionalHeight()
    }

    func setWallRecoveryActive(_ active: Bool) {
        guard active != isWallRecoveryActive else { return }
        isWallRecoveryActive = active
        hasReachedWallRecoveryPosition = false
        burstShotsRemaining = 0
        movementMode = .orbiting
        decisionTimer = 0

        if active {
            targetLateralBias = 0
            targetVerticalBias = 0
        } else {
            nextFireTimer = max(
                nextFireTimer,
                TimeInterval.random(in: GameConfig.enemyApproachAttackDelayRange)
            )
            chooseNewBias()
        }
    }

    func updateStationaryPose(deltaTime: TimeInterval) {
        attackFacingLockTimer = max(0, attackFacingLockTimer - deltaTime)
        rig.update(
            deltaTime: deltaTime,
            facingAngle: facingAngle,
            movementStrength: 0
        )
        updateDirectionalHeight()
    }

    func updateReload(deltaTime: TimeInterval) {
        guard ammo < GameConfig.maxAmmo else { return }
        reloadTimer += deltaTime
        while reloadTimer >= GameConfig.reloadInterval {
            reloadTimer -= GameConfig.reloadInterval
            ammo = min(GameConfig.maxAmmo, ammo + 1)
        }
        rig.setAmmoRatio(CGFloat(ammo) / CGFloat(GameConfig.maxAmmo))
    }

    func updateAttack(deltaTime: TimeInterval) -> AttackUpdateResult {
        if isThrowQueued {
            throwReleaseTimer -= deltaTime
            if throwReleaseTimer <= 0 {
                isThrowQueued = false
                rig.releaseProjectile()
                guard let queuedShotContext else { return .none }
                self.queuedShotContext = nil
                return .releaseProjectile(queuedShotContext)
            }
            return .none
        }

        nextFireTimer -= deltaTime
        if isWallRecoveryActive && !hasReachedWallRecoveryPosition {
            return .none
        }
        guard nextFireTimer <= 0, ammo > 0 else { return .none }
        guard currentPlayerDistance <= GameConfig.enemyThornAttackPositionDistance
            + GameConfig.enemyThornAttackDistanceTolerance else { return .none }
        if isArenaEdgePressureActive {
            guard currentPlayerDistance >= GameConfig.enemyThornAttackPositionDistance
                - GameConfig.enemyThornAttackDistanceTolerance else { return .none }
        }
        if movementMode == .approaching,
           currentPlayerDistance > GameConfig.enemyApproachFireDistance {
            return .none
        }

        if burstShotsRemaining == 0 {
            beginBurst()
        }

        let shotContext = ShotContext(
            burstIndex: activeBurstShotIndex,
            burstCount: activeBurstSize,
            aimStyle: activeAimStyles[activeBurstShotIndex]
        )
        queuedShotContext = shotContext
        activeBurstShotIndex += 1
        burstShotsRemaining -= 1
        ammo -= 1

        if GameConfig.autoAttackTestEnabled {
            burstShotsRemaining = 0
            nextFireTimer = GameConfig.autoAttackRepeatFireDelay
        } else if burstShotsRemaining > 0 {
            nextFireTimer = TimeInterval.random(in: GameConfig.enemyBurstShotDelayRange)
        } else if isWallRecoveryActive {
            nextFireTimer = TimeInterval.random(
                in: GameConfig.enemyWallRecoveryAttackIntervalRange
            )
        } else {
            nextFireTimer = TimeInterval.random(in: GameConfig.enemyAttackIntervalRange)
        }
        throwReleaseTimer = GameConfig.enemyThrowReleaseTime
        isThrowQueued = true
        rig.beginThrow()
        rig.setAmmoRatio(CGFloat(ammo) / CGFloat(GameConfig.maxAmmo))
        if movementMode == .approaching {
            beginRetreat()
        }
        return .beganThrow(shotContext)
    }

    private func beginBurst() {
        let requestedShotCount = GameConfig.autoAttackTestEnabled
            || movementMode == .approaching
            ? 1
            : randomBurstSize()
        activeBurstSize = min(requestedShotCount, ammo)
        burstShotsRemaining = activeBurstSize
        activeBurstShotIndex = 0

        // Keep the automated visual check deterministic. Normal combat shuffles
        // the three aim types so rapid shots pressure different dodge lines.
        if GameConfig.autoAttackTestEnabled {
            activeAimStyles = [.direct]
        } else if isArenaEdgePressureActive {
            // A stationary player must not become safe just by occupying an
            // arena corner. Start every edge-pressure group on the player;
            // follow-up shots still cover random escape lines.
            activeAimStyles = [.direct]
            if activeBurstSize > 1 {
                activeAimStyles.append(
                    contentsOf: Array([AimStyle.smallOffset, .largeOffset]
                        .shuffled()
                        .prefix(activeBurstSize - 1))
                )
            }
        } else {
            activeAimStyles = Array(AimStyle.allCases.shuffled().prefix(activeBurstSize))
        }
    }

    private func randomBurstSize() -> Int {
        let totalWeight = GameConfig.enemySingleShotWeight
            + GameConfig.enemyDoubleShotWeight
            + GameConfig.enemyTripleShotWeight
        let roll = Int.random(in: 0..<totalWeight)
        if roll < GameConfig.enemySingleShotWeight {
            return 1
        }
        if roll < GameConfig.enemySingleShotWeight + GameConfig.enemyDoubleShotWeight {
            return 2
        }
        return 3
    }

    private func chooseBias() {
        if isWallRecoveryActive {
            chooseNewBias()
            return
        }
        if movementMode == .retreating {
            chooseNewBias()
            return
        }

        let baseRange = GameConfig.mapSize.width * GameConfig.enemyHorizontalDriftRangeRatio
        targetLateralBias = CGFloat.random(in: -baseRange...baseRange)
        targetVerticalBias = CGFloat.random(in: GameConfig.enemyVerticalDriftRange)
        let canStartApproach = !isThrowQueued && burstShotsRemaining == 0
        if canStartApproach, CGFloat.random(in: 0...1) < GameConfig.enemyApproachChance {
            movementMode = .approaching
            nextFireTimer = min(
                nextFireTimer,
                TimeInterval.random(in: GameConfig.enemyApproachAttackDelayRange)
            )
        } else {
            movementMode = .orbiting
        }
        chooseNewBias()
    }

    private func beginRetreat() {
        movementMode = .retreating
        targetVerticalBias = GameConfig.tileSize * 1.0
        decisionTimer = 0
        decisionDuration = GameConfig.enemyDecisionDurationRange.upperBound
    }

    private func finishRetreat() {
        movementMode = .orbiting
        targetVerticalBias = CGFloat.random(in: (GameConfig.tileSize * 0.15)...(GameConfig.tileSize * 1.0))
        chooseNewBias()
    }

    private func chooseNewBias() {
        decisionTimer = 0
        decisionDuration = TimeInterval.random(in: GameConfig.enemyDecisionDurationRange)
    }

    private func rotatedAngle(from current: CGFloat, toward target: CGFloat, maxStep: CGFloat) -> CGFloat {
        let fullTurn = CGFloat.pi * 2
        var difference = (target - current).truncatingRemainder(dividingBy: fullTurn)
        if difference > .pi { difference -= fullTurn }
        if difference < -.pi { difference += fullTurn }
        return current + min(max(difference, -maxStep), maxStep)
    }

    private func updateDirectionalHeight() {
        // Normalize the enemy's apparent ear-to-foot height to 6.5 mm across
        // the same perspective angles used by the player model.
        let fullTurn = CGFloat.pi * 2
        var normalizedAngle = facingAngle.truncatingRemainder(dividingBy: fullTurn)
        if normalizedAngle < 0 { normalizedAngle += fullTurn }
        let angleFromToward = min(normalizedAngle, fullTurn - normalizedAngle)

        let anchors: [(angle: CGFloat, scale: CGFloat)] = [
            (0, 6.5 / 7.0),
            (.pi / 2, 7.0 / 8.0),
            (.pi * 3 / 4, 6.5 / 7.0),
            (.pi, 1.0)
        ]
        let upperIndex = anchors.firstIndex { angleFromToward <= $0.angle } ?? anchors.count - 1
        let directionalScale: CGFloat
        if upperIndex == 0 {
            directionalScale = anchors[0].scale
        } else {
            let lower = anchors[upperIndex - 1]
            let upper = anchors[upperIndex]
            let progress = (angleFromToward - lower.angle) / (upper.angle - lower.angle)
            let easedProgress = progress * progress * (3 - 2 * progress)
            directionalScale = lower.scale + (upper.scale - lower.scale) * easedProgress
        }

        let displayScale = GameConfig.enemyModelDisplaySize.width
            / GameConfig.playerModelViewportSize.width
        modelNode.yScale = displayScale * GameConfig.enemyModelHeightScale * directionalScale
    }
}

private final class EnemyFigureRig {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let rootNode = SCNNode()
    private let bodyNode = SCNNode()
    private let torsoNode = SCNNode()
    private let headNode = SCNNode()
    private let scarfNode = SCNNode()
    private let leftLegPivot = SCNNode()
    private let rightLegPivot = SCNNode()
    private let leftArmPivot = SCNNode()
    private let rightArmPivot = SCNNode()
    private let leftHandNode = SCNNode()
    private let rightHandNode = SCNNode()
    private let projectileNode = SCNNode()
    private let ammoGlow = SCNNode()

    private var walkPhase: CGFloat = 0
    private var throwTimeRemaining: TimeInterval = 0
    private var hasReleasedProjectile = false

    init() {
        scene.background.contents = UIColor.clear
        configureCamera()
        configureLights()
        configureFigure()
    }

    func resetPose() {
        walkPhase = 0
        throwTimeRemaining = 0
        rootNode.eulerAngles = SCNVector3(0, 0, 0)
        bodyNode.position = SCNVector3(0, 0.68, 0)
        bodyNode.eulerAngles = SCNVector3(0, 0, 0)
        torsoNode.eulerAngles = SCNVector3(0, 0, 0)
        leftLegPivot.eulerAngles = SCNVector3(0, 0, 0)
        rightLegPivot.eulerAngles = SCNVector3(0, 0, 0)
        leftArmPivot.eulerAngles = SCNVector3(0, 0, 0)
        rightArmPivot.eulerAngles = SCNVector3(0, 0, 0)
        leftArmPivot.position = SCNVector3(-0.31, 0.34, 0.10)
        rightArmPivot.position = SCNVector3(0.31, 0.34, 0.10)
        projectileNode.isHidden = false
        hasReleasedProjectile = false
        setAmmoRatio(1)
    }

    func update(deltaTime: TimeInterval, facingAngle: CGFloat, movementStrength: CGFloat) {
        rootNode.eulerAngles.y = Float(facingAngle)

        let clampedStrength = min(1, max(0, movementStrength))
        walkPhase += CGFloat(deltaTime) * (6.4 + clampedStrength * 3.2)
        throwTimeRemaining = max(0, throwTimeRemaining - deltaTime)
        let throwProgress = throwTimeRemaining > 0
            ? 1 - CGFloat(throwTimeRemaining / GameConfig.enemyThrowDuration)
            : 0

        let legSwing = sin(walkPhase) * 0.42 * clampedStrength
        let armSwing = sin(walkPhase) * 0.24 * clampedStrength
        let bodyBob = abs(sin(walkPhase)) * 0.08 * clampedStrength
        let throwWindup = easedPhase(progress: throwProgress, start: 0.0, end: 0.32)
        let throwRelease = easedPhase(progress: throwProgress, start: 0.32, end: 0.52)
        let throwFollowThrough = easedPhase(progress: throwProgress, start: 0.52, end: 0.74)
        let throwRecover = easedPhase(progress: throwProgress, start: 0.74, end: 1.0)
        let poseWeight = 1 - throwRecover

        // Reference motion: right shoulder pulls back, the hand rises clearly
        // above the head, then snaps forward and down through an overhand arc.
        let throwingArmLift = (2.72 * throwWindup - 1.52 * throwRelease - 0.84 * throwFollowThrough) * poseWeight
        let throwingArmDepth = (0.82 * throwWindup - 1.58 * throwRelease - 0.28 * throwFollowThrough) * poseWeight
        let throwingArmSweep = (-0.74 * throwWindup + 0.92 * throwRelease + 0.18 * throwFollowThrough) * poseWeight
        let torsoTwist = (0.58 * throwWindup - 0.94 * throwRelease + 0.20 * throwFollowThrough) * poseWeight
        let torsoLean = (-0.16 * throwWindup + 0.34 * throwRelease + 0.10 * throwFollowThrough) * poseWeight
        let throwCrouch = (0.08 * throwWindup - 0.05 * throwRelease) * poseWeight
        let throwingShoulderLift = (0.82 * throwWindup - 0.60 * throwRelease - 0.22 * throwFollowThrough) * poseWeight
        let throwingShoulderTuck = (-0.10 * throwWindup + 0.08 * throwRelease) * poseWeight

        if !hasReleasedProjectile, throwProgress >= CGFloat(GameConfig.enemyThrowReleaseTime / GameConfig.enemyThrowDuration) {
            projectileNode.isHidden = true
            hasReleasedProjectile = true
        }

        bodyNode.position.y = 0.68 + Float(bodyBob - throwCrouch)
        torsoNode.eulerAngles.y = Float(torsoTwist)
        torsoNode.eulerAngles.z = Float(-torsoTwist * 0.16)
        bodyNode.eulerAngles.x = Float(torsoLean)
        leftLegPivot.eulerAngles.x = Float(-legSwing)
        rightLegPivot.eulerAngles.x = Float(legSwing)
        leftArmPivot.position = SCNVector3(
            -0.31 - Float(throwingShoulderTuck),
            0.34 + Float(throwingShoulderLift),
            0.10
        )
        leftArmPivot.eulerAngles.x = Float(-0.18 + armSwing + throwingArmDepth)
        leftArmPivot.eulerAngles.y = Float(0.22 - throwingArmSweep)
        leftArmPivot.eulerAngles.z = Float(0.34 - throwingArmLift)
        rightArmPivot.position = SCNVector3(0.31, 0.34, 0.10)
        rightArmPivot.eulerAngles.x = Float(-armSwing - throwRelease * 0.16 * poseWeight)
        rightArmPivot.eulerAngles.y = 0
        rightArmPivot.eulerAngles.z = Float(-0.10 - throwWindup * 0.20 * poseWeight)
    }

    func setFacingAngle(_ angle: CGFloat) {
        rootNode.eulerAngles.y = Float(angle)
    }

    func setAmmoRatio(_ ratio: CGFloat) {
        let color = UIColor(
            red: 1.0,
            green: 0.35 + 0.45 * ratio,
            blue: 0.18,
            alpha: 1
        )
        ammoGlow.geometry?.firstMaterial?.emission.contents = color
    }

    func beginThrow() {
        throwTimeRemaining = GameConfig.enemyThrowDuration
        projectileNode.isHidden = false
        hasReleasedProjectile = false
        let action = SCNAction.sequence([
            .scale(to: 1.24, duration: 0.06),
            .scale(to: 1.0, duration: 0.12)
        ])
        projectileNode.removeAllActions()
        projectileNode.runAction(action)
    }

    func releaseProjectile() {
        projectileNode.isHidden = true
        hasReleasedProjectile = true
    }

    private func configureCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.01
        camera.zFar = 20
        cameraNode.camera = camera
        // Match the player's five-degree steeper view while preserving the
        // distance to the enemy model's visual center.
        cameraNode.position = SCNVector3(0, 3.461, 2.211)
        cameraNode.eulerAngles = SCNVector3(-0.7973, 0, 0)
        scene.rootNode.addChildNode(cameraNode)
    }

    private func configureLights() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 900
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 1_500
        key.position = SCNVector3(1.8, 5.0, 2.0)
        scene.rootNode.addChildNode(key)
    }

    private func configureFigure() {
        scene.rootNode.addChildNode(rootNode)

        bodyNode.position = SCNVector3(0, 0.68, 0)
        rootNode.addChildNode(bodyNode)

        // Enemy: an original plant shaman made from bark, moss and seed pods.
        // Its silhouette deliberately shares no costume language with the player.
        torsoNode.geometry = SCNCapsule(capRadius: 0.34, height: 0.96)
        torsoNode.geometry?.firstMaterial = material(color: UIColor(red: 0.27, green: 0.16, blue: 0.10, alpha: 1))
        torsoNode.position = SCNVector3(0, 0.72, 0)
        bodyNode.addChildNode(torsoNode)

        let mossWrap = SCNNode(geometry: SCNBox(width: 0.74, height: 0.50, length: 0.28, chamferRadius: 0.14))
        mossWrap.geometry?.firstMaterial = material(color: UIColor(red: 0.24, green: 0.44, blue: 0.20, alpha: 1))
        mossWrap.position = SCNVector3(0, 0.00, 0.22)
        torsoNode.addChildNode(mossWrap)

        for y in [-0.18, 0.04, 0.24] {
            let barkBand = SCNNode(geometry: SCNTorus(ringRadius: 0.29, pipeRadius: 0.025))
            barkBand.geometry?.firstMaterial = material(color: UIColor(red: 0.48, green: 0.29, blue: 0.13, alpha: 1))
            barkBand.eulerAngles.x = .pi / 2
            barkBand.position = SCNVector3(0, Float(y), 0.10)
            torsoNode.addChildNode(barkBand)
        }

        headNode.geometry = SCNSphere(radius: 0.38)
        headNode.geometry?.firstMaterial = material(color: UIColor(red: 0.34, green: 0.19, blue: 0.12, alpha: 1))
        headNode.scale = SCNVector3(1.06, 0.96, 1.02)
        headNode.position = SCNVector3(0, 1.30, 0.08)
        bodyNode.addChildNode(headNode)

        let facePatch = SCNNode(geometry: SCNBox(width: 0.42, height: 0.24, length: 0.08, chamferRadius: 0.10))
        facePatch.geometry?.firstMaterial = material(color: UIColor(red: 0.18, green: 0.10, blue: 0.08, alpha: 1))
        facePatch.position = SCNVector3(0, -0.02, 0.34)
        headNode.addChildNode(facePatch)

        for x in [-0.10, 0.10] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.035))
            eye.geometry?.firstMaterial = material(
                color: UIColor(red: 0.96, green: 0.72, blue: 0.18, alpha: 1),
                emission: UIColor(red: 0.40, green: 0.18, blue: 0.02, alpha: 0.32)
            )
            eye.position = SCNVector3(Float(x), 0.02, 0.055)
            facePatch.addChildNode(eye)
        }

        let leafMaterial = material(color: UIColor(red: 0.30, green: 0.58, blue: 0.20, alpha: 1))
        for (x, angle) in [(-0.28, -0.55), (0.0, 0.0), (0.28, 0.55)] {
            let leaf = SCNNode(geometry: SCNCone(topRadius: 0.0, bottomRadius: 0.16, height: 0.40))
            leaf.geometry?.firstMaterial = leafMaterial
            leaf.position = SCNVector3(Float(x), 0.36, 0.0)
            leaf.eulerAngles.z = Float(angle)
            headNode.addChildNode(leaf)
        }

        scarfNode.geometry = SCNTorus(ringRadius: 0.28, pipeRadius: 0.065)
        scarfNode.geometry?.firstMaterial = material(color: UIColor(red: 0.45, green: 0.64, blue: 0.22, alpha: 1))
        scarfNode.eulerAngles.x = .pi / 2
        scarfNode.position = SCNVector3(0, 0.94, 0.10)
        bodyNode.addChildNode(scarfNode)

        ammoGlow.geometry = SCNSphere(radius: 0.10)
        ammoGlow.geometry?.firstMaterial = material(
            color: UIColor(red: 0.95, green: 0.42, blue: 0.18, alpha: 1),
            emission: UIColor(red: 0.44, green: 0.12, blue: 0.02, alpha: 0.45)
        )
        ammoGlow.position = SCNVector3(-0.20, 0.12, 0.30)
        torsoNode.addChildNode(ammoGlow)

        configureArm(pivot: leftArmPivot, side: -1)
        configureArm(pivot: rightArmPivot, side: 1)
        configureLeg(pivot: leftLegPivot, side: -1)
        configureLeg(pivot: rightLegPivot, side: 1)

        projectileNode.geometry = SCNSphere(radius: 0.12)
        projectileNode.geometry?.firstMaterial = material(
            color: UIColor(red: 0.86, green: 0.24, blue: 0.14, alpha: 1),
            emission: UIColor(red: 0.52, green: 0.08, blue: 0.03, alpha: 0.58)
        )
        projectileNode.position = SCNVector3(-0.18, -0.10, 0.18)
        leftHandNode.addChildNode(projectileNode)

        for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 3) {
            let spike = SCNNode(geometry: SCNCone(topRadius: 0.0, bottomRadius: 0.035, height: 0.16))
            spike.geometry?.firstMaterial = material(
                color: UIColor(red: 0.98, green: 0.48, blue: 0.16, alpha: 1),
                emission: UIColor(red: 0.46, green: 0.12, blue: 0.02, alpha: 0.32)
            )
            spike.position = SCNVector3(Float(cos(angle)) * 0.10, Float(sin(angle)) * 0.10, 0)
            spike.eulerAngles = SCNVector3(.pi / 2, 0, Float(angle) + .pi / 2)
            projectileNode.addChildNode(spike)
        }

    }

    private func configureArm(pivot: SCNNode, side: Float) {
        pivot.position = SCNVector3(0.31 * side, 0.34, 0.10)
        bodyNode.addChildNode(pivot)

        let arm = SCNNode(geometry: SCNCapsule(capRadius: 0.10, height: 0.46))
        arm.geometry?.firstMaterial = material(color: UIColor(red: 0.34, green: 0.20, blue: 0.11, alpha: 1))
        arm.position = SCNVector3(0.12 * side, -0.20, 0.02)
        arm.eulerAngles.z = side < 0 ? 0.24 : -0.24
        pivot.addChildNode(arm)

        let forearmBand = SCNNode(geometry: SCNTorus(ringRadius: 0.09, pipeRadius: 0.025))
        forearmBand.geometry?.firstMaterial = material(color: UIColor(red: 0.39, green: 0.58, blue: 0.20, alpha: 1))
        forearmBand.eulerAngles.x = .pi / 2
        forearmBand.position = SCNVector3(0.17 * side, -0.32, 0.02)
        pivot.addChildNode(forearmBand)

        let hand = side < 0 ? leftHandNode : rightHandNode
        hand.geometry = SCNSphere(radius: 0.10)
        hand.geometry?.firstMaterial = material(color: UIColor(red: 0.43, green: 0.27, blue: 0.13, alpha: 1))
        hand.position = SCNVector3(0.21 * side, -0.38, 0.06)
        pivot.addChildNode(hand)
    }

    private func configureLeg(pivot: SCNNode, side: Float) {
        pivot.position = SCNVector3(0.24 * side, 0.20, 0.02)
        bodyNode.addChildNode(pivot)

        let leg = SCNNode(geometry: SCNCapsule(capRadius: 0.11, height: 0.44))
        leg.geometry?.firstMaterial = material(color: UIColor(red: 0.30, green: 0.18, blue: 0.10, alpha: 1))
        leg.position = SCNVector3(0, -0.20, 0)
        pivot.addChildNode(leg)

        let foot = SCNNode(geometry: SCNBox(width: 0.34, height: 0.14, length: 0.34, chamferRadius: 0.07))
        foot.geometry?.firstMaterial = material(color: UIColor(red: 0.36, green: 0.23, blue: 0.11, alpha: 1))
        foot.position = SCNVector3(0, -0.44, 0.08)
        pivot.addChildNode(foot)

        let sole = SCNNode(geometry: SCNBox(width: 0.34, height: 0.035, length: 0.34, chamferRadius: 0.02))
        sole.geometry?.firstMaterial = material(color: UIColor(red: 0.19, green: 0.12, blue: 0.07, alpha: 1))
        sole.position = SCNVector3(0, -0.07, 0)
        foot.addChildNode(sole)
    }

    private func material(color: UIColor, emission: UIColor = .black) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = emission
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.86
        material.metalness.contents = 0.0
        return material
    }

    private func easedPhase(progress: CGFloat, start: CGFloat, end: CGFloat) -> CGFloat {
        guard end > start else { return 0 }
        let t = min(1, max(0, (progress - start) / (end - start)))
        return t * t * (3 - 2 * t)
    }
}
