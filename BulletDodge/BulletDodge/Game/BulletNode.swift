import SpriteKit
import UIKit

struct BulletMotion {
    var angularVelocity: CGFloat
    var curveDelay: TimeInterval

    static let linear = BulletMotion(angularVelocity: 0, curveDelay: .infinity)
}

struct ShardKeyframe {
    let time: TimeInterval
    let radius: CGFloat
    let sweepDegrees: CGFloat
}

struct ShardFacingKeyframe {
    let time: TimeInterval
    let offsetDegrees: CGFloat
}

struct ShardBurstTemplate {
    let angleDegrees: CGFloat
    let keyframes: [ShardKeyframe]
}

struct ExplosionSpec {
    let position: CGPoint
    let damagePosition: CGPoint
    let splashRadius: CGFloat
    let splashDamage: CGFloat
    let fragments: [FragmentSpec]
}

struct FragmentSpec {
    let direction: CGVector
    let angularVelocity: CGFloat
    let keyframes: [ShardKeyframe]
}

enum BulletOutcome {
    case active
    case expired
    case explode(ExplosionSpec)
}

final class BulletNode: SKNode {
    enum Kind {
        case thornBall
        case thornShard
    }

    private let kind: Kind
    private let motion: BulletMotion
    private let fuseDuration: TimeInterval?
    private let collisionDelay: TimeInterval
    private let shadowNode: SKShapeNode
    private let trailNode: SKShapeNode
    private let orbitRoot = SKNode()
    private let visualRoot = SKNode()
    private let spriteNode: SKSpriteNode
    private let keyframes: [ShardKeyframe]?

    private(set) var direction: CGVector
    private(set) var moveSpeed: CGFloat
    private(set) var range: CGFloat
    private(set) var damage: CGFloat
    private(set) var radius: CGFloat
    private(set) var contactRadius: CGFloat
    private(set) var traveledDistance: CGFloat = 0
    private(set) var hasDealtDamage = false

    private var lifetime: TimeInterval = 0
    private let spinSeed = CGFloat.random(in: 0...(CGFloat.pi * 2))
    private let spawnDirection: CGVector
    private var facingDirection: CGVector
    private var radialDirection: CGVector
    private var pathOrigin: CGPoint?
    private var previousGroundContactPosition: CGPoint?

    private init(
        kind: Kind,
        direction: CGVector,
        moveSpeed: CGFloat,
        range: CGFloat,
        damage: CGFloat,
        radius: CGFloat,
        contactRadius: CGFloat,
        motion: BulletMotion,
        keyframes: [ShardKeyframe]? = nil,
        fuseDuration: TimeInterval? = nil,
        collisionDelay: TimeInterval = 0
    ) {
        self.kind = kind
        self.direction = direction.normalized
        self.spawnDirection = direction.normalized
        self.facingDirection = direction.normalized
        self.radialDirection = direction.normalized
        self.moveSpeed = moveSpeed
        self.range = range
        self.damage = damage
        self.radius = radius
        self.contactRadius = contactRadius
        self.motion = motion
        self.keyframes = keyframes
        self.fuseDuration = fuseDuration
        self.collisionDelay = collisionDelay

        let trailSize = kind == .thornBall
            ? CGSize(width: radius * 0.56, height: radius * 1.14)
            : CGSize(width: radius * 0.18, height: radius * 0.70)
        // Size the ground shadow from the visible art rather than the larger
        // collision/animation radius.  A thin oval reads as a cast shadow while
        // leaving enough space below the projectile to show that it is airborne.
        let shadowSize = kind == .thornBall
            ? CGSize(
                width: GameConfig.thornBallVisualDiameter * 0.76,
                height: GameConfig.thornBallVisualDiameter * 0.30
            )
            : CGSize(
                width: GameConfig.thornShardVisualLength * 0.74,
                height: GameConfig.thornShardVisualWidth * 0.27
            )

        shadowNode = SKShapeNode(ellipseOf: shadowSize)
        trailNode = SKShapeNode(rectOf: trailSize, cornerRadius: trailSize.width * 0.5)
        let spriteTexture = kind == .thornBall ? Self.ballTexture : Self.shardTexture
        let spriteSize: CGSize
        switch kind {
        case .thornBall:
            // Compensate for transparent padding in the 512 px source image so the
            // non-transparent projectile itself measures exactly 5 mm on screen.
            spriteSize = CGSize(
                width: GameConfig.thornBallVisualDiameter / 0.7097,
                height: GameConfig.thornBallVisualDiameter / 0.6922
            )
        case .thornShard:
            // The originalized source points horizontally right. Compensate for its
            // transparent padding so the visible thorn stays exactly 4 x 2.5 mm.
            spriteSize = CGSize(
                width: GameConfig.thornShardVisualLength / 0.5227,
                height: GameConfig.thornShardVisualWidth / 0.5282
            )
        }
        spriteNode = SKSpriteNode(texture: spriteTexture, size: spriteSize)

        super.init()

        shadowNode.fillColor = UIColor.black.withAlphaComponent(kind == .thornBall ? 0.28 : 0.23)
        shadowNode.strokeColor = .clear
        shadowNode.glowWidth = kind == .thornBall ? 2.2 : 1.4
        addChild(shadowNode)

        trailNode.fillColor = UIColor(red: 0.48, green: 0.96, blue: 1.0, alpha: kind == .thornBall ? 0.14 : 0.18)
        trailNode.strokeColor = .clear
        trailNode.glowWidth = kind == .thornBall ? 2.0 : 1.2
        addChild(trailNode)

        orbitRoot.zPosition = -1
        addChild(orbitRoot)
        if kind == .thornBall {
            configureBallOrbitEffect()
        }

        addChild(visualRoot)
        spriteNode.blendMode = .alpha
        visualRoot.addChild(spriteNode)

        updateVisuals(deltaTime: 0)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    static func thornBall(direction: CGVector) -> BulletNode {
        BulletNode(
            kind: .thornBall,
            direction: direction,
            moveSpeed: GameConfig.thornBallSpeed,
            range: GameConfig.thornBallRange,
            damage: GameConfig.thornBallDamage,
            radius: GameConfig.thornBallRadius,
            contactRadius: GameConfig.thornBallContactRadius,
            motion: .linear,
            fuseDuration: GameConfig.thornBallLifetime
        )
    }

    static func thornShard(direction: CGVector, angularVelocity: CGFloat, keyframes: [ShardKeyframe]) -> BulletNode {
        BulletNode(
            kind: .thornShard,
            direction: direction,
            moveSpeed: GameConfig.thornShardSpeed,
            range: GameConfig.thornShardRange,
            damage: GameConfig.thornShardDamage,
            radius: GameConfig.thornShardRadius,
            contactRadius: GameConfig.thornShardContactRadius,
            motion: BulletMotion(angularVelocity: angularVelocity, curveDelay: GameConfig.thornShardCurveDelay),
            keyframes: keyframes,
            collisionDelay: GameConfig.thornShardCollisionDelay
        )
    }

    static func prewarmVisualResources() {
        SKTexture.preload([ballTexture, shardTexture, burstTexture]) { }
    }

    @discardableResult
    func update(deltaTime: TimeInterval) -> BulletOutcome {
        let groundContactPositionBeforeMovement = groundContactPosition
        let movementDeltaTime: TimeInterval
        if case .thornBall = kind, let fuseDuration {
            // Stop exactly at the fuse endpoint instead of overshooting by up to one frame.
            movementDeltaTime = min(deltaTime, max(0, fuseDuration - lifetime))
        } else {
            movementDeltaTime = deltaTime
        }
        lifetime += movementDeltaTime

        if let keyframes {
            if pathOrigin == nil {
                pathOrigin = position
            }

            let previousPosition = position
            applyKeyframedMotion(keyframes: keyframes)
            let delta = CGVector(dx: position.x - previousPosition.x, dy: position.y - previousPosition.y)
            traveledDistance += delta.length
            if delta.length > 0.001 {
                direction = delta.normalized
            }
            updateShardFacingDirection()
            updateVisuals(deltaTime: deltaTime)
            previousGroundContactPosition = groundContactPositionBeforeMovement

            if lifetime >= (keyframes.last?.time ?? 0) {
                return .expired
            }
            return .active
        }

        if lifetime >= motion.curveDelay, motion.angularVelocity != 0 {
            direction = direction.rotated(by: motion.angularVelocity * CGFloat(deltaTime)).normalized
        }

        let delta = direction * (moveSpeed * CGFloat(movementDeltaTime))
        position = CGPoint(x: position.x + delta.dx, y: position.y + delta.dy)
        traveledDistance += delta.length
        updateVisuals(deltaTime: movementDeltaTime)
        previousGroundContactPosition = groundContactPositionBeforeMovement

        if case .thornBall = kind, let fuseDuration, lifetime >= fuseDuration {
            return .explode(makeExplosionSpec())
        }

        if traveledDistance >= range {
            if case .thornBall = kind {
                return .explode(makeExplosionSpec())
            }
            return .expired
        }

        return .active
    }

    func registerHit() {
        hasDealtDamage = true
    }

    func primeSpawnPose() {
        guard keyframes != nil else { return }
        guard pathOrigin == nil else { return }
        pathOrigin = position
        lifetime = 0.001
        if let keyframes {
            applyKeyframedMotion(keyframes: keyframes)
        }
        updateVisuals(deltaTime: 0)
    }

    var isTimedParent: Bool {
        if case .thornBall = kind {
            return true
        }
        return false
    }

    var canDealContactDamage: Bool {
        lifetime >= collisionDelay
    }

    func contactExplosionSpec() -> ExplosionSpec? {
        guard isTimedParent else { return nil }
        return makeExplosionSpec()
    }

    func intersectsPlayer(at playerPosition: CGPoint) -> Bool {
        // Character and projectile art may be rendered above the arena plane,
        // but Brawl-style damage is resolved entirely in 2D on that plane.
        // The projectile shadow marks its ground position; model depth and
        // front/back rendering order must never affect contact.
        let combinedRadius = GameConfig.playerHitRadius + contactRadius
        let distanceSquared: CGFloat
        switch kind {
        case .thornBall:
            let deltaX = groundContactPosition.x - playerPosition.x
            let deltaY = groundContactPosition.y - playerPosition.y
            distanceSquared = deltaX * deltaX + deltaY * deltaY
        case .thornShard:
            // Test the complete path covered during this rendered frame.
            // A fast thorn must not tunnel through the 2D player circle when
            // frame duration varies or a frame is dropped.
            distanceSquared = Self.squaredDistance(
                from: playerPosition,
                toSegmentFrom: previousGroundContactPosition ?? groundContactPosition,
                through: groundContactPosition
            )
        }
        return distanceSquared <= combinedRadius * combinedRadius
    }

    private var groundContactPosition: CGPoint {
        CGPoint(
            x: position.x + shadowNode.position.x,
            y: position.y + shadowNode.position.y
        )
    }

    private static func squaredDistance(
        from point: CGPoint,
        toSegmentFrom start: CGPoint,
        through end: CGPoint
    ) -> CGFloat {
        let segmentX = end.x - start.x
        let segmentY = end.y - start.y
        let lengthSquared = segmentX * segmentX + segmentY * segmentY
        guard lengthSquared > 0.000_001 else {
            let deltaX = point.x - end.x
            let deltaY = point.y - end.y
            return deltaX * deltaX + deltaY * deltaY
        }

        let projection = (
            (point.x - start.x) * segmentX
                + (point.y - start.y) * segmentY
        ) / lengthSquared
        let clampedProjection = min(1, max(0, projection))
        let closestX = start.x + segmentX * clampedProjection
        let closestY = start.y + segmentY * clampedProjection
        let deltaX = point.x - closestX
        let deltaY = point.y - closestY
        return deltaX * deltaX + deltaY * deltaY
    }

    private func makeExplosionSpec() -> ExplosionSpec {
        let fragments = Self.shardBurstTemplates.map { template in
            let worldVector = direction.rotated(by: template.angleDegrees * (.pi / 180))
            return FragmentSpec(
                direction: worldVector.normalized,
                angularVelocity: 0,
                keyframes: template.keyframes
            )
        }

        return ExplosionSpec(
            position: position,
            damagePosition: groundContactPosition,
            // The parent projectile keeps one fixed 2D contact circle through
            // flight and landing. The burst artwork does not enlarge damage.
            splashRadius: contactRadius,
            splashDamage: GameConfig.explosionDamage,
            fragments: fragments
        )
    }

    private func updateVisuals(deltaTime: TimeInterval) {
        let visualDirection = kind == .thornShard ? facingDirection : direction
        let heading = atan2(visualDirection.dy, visualDirection.dx)
        let pulse = 1 + sin(CGFloat(lifetime) * 16 + spinSeed) * 0.03

        trailNode.zRotation = heading - .pi / 2
        trailNode.position = CGPoint(
            x: -visualDirection.dx * radius * (kind == .thornBall ? 0.62 : 0.54),
            y: -visualDirection.dy * radius * (kind == .thornBall ? 0.62 : 0.54)
        )
        trailNode.xScale = 1.0
        trailNode.yScale = kind == .thornBall ? 0.84 + pulse * 0.06 : 0.40
        trailNode.alpha = kind == .thornShard ? 0.34 : 0

        switch kind {
        case .thornBall:
            zRotation = 0
            visualRoot.position = .zero
            visualRoot.zRotation += CGFloat(deltaTime) * 2.8
            visualRoot.setScale(1.0 + (pulse - 1) * 0.20)
            spriteNode.alpha = 1.0
            orbitRoot.zRotation -= CGFloat(deltaTime) * 7.2
            orbitRoot.alpha = 0.72 + sin(CGFloat(lifetime) * 18) * 0.12
            // Keep the shadow visibly below the art. Previously it sat underneath
            // the transparent-padded sprite and was almost completely hidden.
            shadowNode.position = CGPoint(
                x: GameConfig.thornBallVisualDiameter * 0.05,
                y: -GameConfig.thornBallVisualDiameter * 0.66
            )
            shadowNode.setScale(1.0)
            shadowNode.alpha = 1.0
        case .thornShard:
            // Keep the node in world axes so the trail is not rotated twice.
            // Only the thorn art follows the delayed turn toward the path tangent.
            zRotation = 0
            visualRoot.zRotation = heading
            visualRoot.setScale(0.96 + min(CGFloat(lifetime) * 0.75, 0.10))
            shadowNode.position = CGPoint(
                x: GameConfig.thornShardVisualLength * 0.05,
                y: -GameConfig.thornShardVisualWidth * 0.78
            )
            let finalTime = keyframes?.last?.time ?? GameConfig.thornShardFlightDuration
            // The reference thorn stays fully readable through most of its flight
            // and only becomes translucent during the final tenth of a second.
            let fadeStart = finalTime * 0.84
            let fadeProgress = max(0, min(1, CGFloat((lifetime - fadeStart) / max(finalTime - fadeStart, 0.001))))
            let visibility = 1.0 - fadeProgress
            spriteNode.alpha = visibility
            shadowNode.alpha = visibility
            trailNode.alpha = 0.34 * visibility
        }
    }

    private func configureBallOrbitEffect() {
        let diameter = GameConfig.thornBallVisualDiameter

        let outerPath = UIBezierPath(
            arcCenter: .zero,
            radius: diameter * 0.58,
            startAngle: .pi * 0.18,
            endAngle: .pi * 1.76,
            clockwise: true
        )
        let outerArc = SKShapeNode(path: outerPath.cgPath)
        outerArc.position = CGPoint(x: -diameter * 0.24, y: 0)
        outerArc.xScale = 1.08
        outerArc.yScale = 0.76
        outerArc.strokeColor = UIColor(red: 1.0, green: 0.73, blue: 0.78, alpha: 0.95)
        outerArc.lineWidth = 1.8
        outerArc.lineCap = .round
        outerArc.glowWidth = 2.2
        orbitRoot.addChild(outerArc)

        let innerPath = UIBezierPath(
            arcCenter: .zero,
            radius: diameter * 0.43,
            startAngle: .pi * 0.96,
            endAngle: .pi * 1.54,
            clockwise: true
        )
        let innerArc = SKShapeNode(path: innerPath.cgPath)
        innerArc.position = CGPoint(x: -diameter * 0.16, y: diameter * 0.02)
        innerArc.xScale = 1.10
        innerArc.yScale = 0.74
        innerArc.strokeColor = UIColor.white.withAlphaComponent(0.76)
        innerArc.lineWidth = 1.2
        innerArc.lineCap = .round
        innerArc.glowWidth = 1.4
        orbitRoot.addChild(innerArc)
    }

    private func applyKeyframedMotion(keyframes: [ShardKeyframe]) {
        guard let origin = pathOrigin else { return }
        let clampedTime = min(lifetime, keyframes.last?.time ?? lifetime)
        let segment = zip(keyframes, keyframes.dropFirst()).first { from, to in
            clampedTime >= from.time && clampedTime <= to.time
        } ?? (keyframes[keyframes.count - 2], keyframes[keyframes.count - 1])

        let duration = max(segment.1.time - segment.0.time, 0.0001)
        let t = CGFloat((clampedTime - segment.0.time) / duration)
        // The frame-tracked reference advances almost linearly between samples.
        // Smooth-stepping every segment creates a visible speed pulse at each keyframe.
        let radius = segment.0.radius + (segment.1.radius - segment.0.radius) * t
        let sweepDegrees = segment.0.sweepDegrees + (segment.1.sweepDegrees - segment.0.sweepDegrees) * t
        let baseAngle = atan2(spawnDirection.dy, spawnDirection.dx)
        let worldAngle = baseAngle + sweepDegrees * (.pi / 180)
        let radial = CGVector(dx: cos(worldAngle), dy: sin(worldAngle))
        radialDirection = radial

        position = CGPoint(
            // Match the reference's on-screen projection without changing the
            // arena/camera scale, which is intentionally different in this app.
            x: origin.x + radial.dx * radius * Self.shardHorizontalDisplacementScale,
            y: origin.y + radial.dy * radius * Self.shardVerticalDisplacementScale
        )
    }

    private func updateShardFacingDirection() {
        guard case .thornShard = kind else {
            facingDirection = direction
            return
        }

        let frames = Self.shardFacingKeyframes
        let clampedTime = min(lifetime, frames.last?.time ?? lifetime)
        let segment = zip(frames, frames.dropFirst()).first { from, to in
            clampedTime >= from.time && clampedTime <= to.time
        } ?? (frames[frames.count - 2], frames[frames.count - 1])
        let duration = max(segment.1.time - segment.0.time, 0.0001)
        let progress = CGFloat((clampedTime - segment.0.time) / duration)
        let offsetDegrees = segment.0.offsetDegrees
            + (segment.1.offsetDegrees - segment.0.offsetDegrees) * progress
        facingDirection = radialDirection.rotated(by: offsetDegrees * (.pi / 180)).normalized
    }

    private static let spiralShardKeyframes: [ShardKeyframe] = [
        // Values measured in the 60 fps reference after correcting for the
        // app/reference camera's unequal horizontal and vertical screen scale.
        // The six thorns are already separated from the burst centre on their
        // first visible frame. The marked reference frame measures ~21 units.
        .init(time: 0.00, radius: 21, sweepDegrees: 0),
        .init(time: 0.10, radius: 40, sweepDegrees: -10),
        .init(time: 0.20, radius: 66, sweepDegrees: -23),
        .init(time: 0.30, radius: 92, sweepDegrees: -34),
        .init(time: 0.40, radius: 118, sweepDegrees: -45),
        .init(time: 0.50, radius: 144, sweepDegrees: -59),
        .init(time: 0.53, radius: 159, sweepDegrees: -66.5),
        .init(time: 0.57, radius: 167, sweepDegrees: -71.5),
        .init(time: 0.60, radius: 168, sweepDegrees: -72.3),
        .init(time: 0.62, radius: 168, sweepDegrees: -72.3)
    ]

    // Screen-space endpoint axes measured from the paired sequences:
    // app 232.75 x 190.80 px, reference 230.88 x 183.12 px.
    private static let shardHorizontalDisplacementScale: CGFloat = 0.992
    private static let shardVerticalDisplacementScale: CGFloat = 0.960

    private static let shardFacingKeyframes: [ShardFacingKeyframe] = [
        .init(time: 0.00, offsetDegrees: 0),
        .init(time: 0.10, offsetDegrees: -10),
        .init(time: 0.20, offsetDegrees: -22),
        .init(time: 0.23, offsetDegrees: -23.5),
        .init(time: 0.28, offsetDegrees: -24.9),
        .init(time: 0.33, offsetDegrees: -27.2),
        .init(time: 0.38, offsetDegrees: -30.2),
        .init(time: 0.43, offsetDegrees: -33.4),
        .init(time: 0.48, offsetDegrees: -37.5),
        .init(time: 0.53, offsetDegrees: -52.4),
        .init(time: 0.57, offsetDegrees: -67.2),
        .init(time: 0.60, offsetDegrees: -70.6),
        .init(time: 0.62, offsetDegrees: -70.6)
    ]

    private static let shardBurstTemplates: [ShardBurstTemplate] = [
        .init(
            angleDegrees: 30,
            keyframes: spiralShardKeyframes
        ),
        .init(
            angleDegrees: 90,
            keyframes: spiralShardKeyframes
        ),
        .init(
            angleDegrees: 150,
            keyframes: spiralShardKeyframes
        ),
        .init(
            angleDegrees: 210,
            keyframes: spiralShardKeyframes
        ),
        .init(
            angleDegrees: 270,
            keyframes: spiralShardKeyframes
        ),
        .init(
            angleDegrees: 330,
            keyframes: spiralShardKeyframes
        )
    ]

    private static let ballTexture = SKTexture(imageNamed: "enemy_attack_ball")
    private static let shardTexture = SKTexture(imageNamed: "enemy_attack_shard")
    static let burstTexture = SKTexture(imageNamed: "enemy_attack_burst")
}
