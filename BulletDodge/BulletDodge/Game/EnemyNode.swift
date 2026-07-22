import SceneKit
import SpriteKit

final class EnemyNode: SKNode {
    enum AttackUpdateResult {
        case none
        case beganThrow
        case releaseProjectile
    }

    private let shadowNode = SKShapeNode(
        ellipseOf: CGSize(
            width: GameConfig.tileSize * 0.74,
            height: GameConfig.tileSize * 0.32
        )
    )
    private let modelNode = SK3DNode(viewportSize: GameConfig.playerModelViewportSize)
    private let rig = EnemyFigureRig()

    private(set) var ammo = GameConfig.maxAmmo

    private var decisionTimer: TimeInterval = 0
    private var decisionDuration: TimeInterval = 0
    private var reloadTimer: TimeInterval = 0
    private var nextFireTimer: TimeInterval = 0
    private var throwReleaseTimer: TimeInterval = 0
    private var isThrowQueued = false
    private var lateralBias: CGFloat = 0
    private var verticalBias: CGFloat = 0
    private var bobTimer: TimeInterval = 0
    private var lastDelta: CGVector = .zero
    private var facingAngle: CGFloat = 0

    override init() {
        super.init()

        shadowNode.position = CGPoint(x: 0, y: -24)
        shadowNode.fillColor = UIColor.black.withAlphaComponent(0.18)
        shadowNode.strokeColor = .clear

        modelNode.scnScene = rig.scene
        modelNode.pointOfView = rig.cameraNode
        let displayScale = GameConfig.enemyModelDisplaySize.width / GameConfig.playerModelViewportSize.width
        modelNode.xScale = displayScale
        modelNode.yScale = displayScale * GameConfig.enemyModelHeightScale
        modelNode.position = CGPoint(x: 0, y: -5)

        addChild(shadowNode)
        addChild(modelNode)

        chooseNewBias()
    }

    required init?(coder aDecoder: NSCoder) {
        nil
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
        bobTimer = 0
        lastDelta = .zero
        facingAngle = 0
        rig.resetPose()
        updateDirectionalHeight()
        chooseNewBias()
    }

    func updateMovement(deltaTime: TimeInterval, desiredAnchor: CGPoint, mapRect: CGRect) {
        decisionTimer += deltaTime
        bobTimer += deltaTime
        if decisionTimer >= decisionDuration {
            chooseBias()
        }

        let bobOffset = sin(bobTimer * GameConfig.enemyBobSpeed) * GameConfig.enemyBobAmplitude
        let targetPoint = CGPoint(
            x: desiredAnchor.x + lateralBias,
            y: desiredAnchor.y + verticalBias + bobOffset
        )
        let toTarget = CGVector(dx: targetPoint.x - position.x, dy: targetPoint.y - position.y)
        let distance = toTarget.length
        let followSpeed = GameConfig.enemySpeed * GameConfig.enemyAnchorFollowStrength
        let maxStep = min(distance, followSpeed * CGFloat(deltaTime))
        let delta = distance > 0 ? toTarget.normalized * maxStep : .zero
        let nextPosition = CGPoint(x: position.x + delta.dx, y: position.y + delta.dy)
        position = nextPosition.clamped(
            in: mapRect.insetBy(dx: GameConfig.enemyCollisionRadius, dy: GameConfig.enemyCollisionRadius)
        )

        lastDelta = deltaTime > 0 ? CGVector(dx: delta.dx / CGFloat(deltaTime), dy: delta.dy / CGFloat(deltaTime)) : .zero
        if lastDelta.length > 1 {
            facingAngle = atan2(lastDelta.dx, -lastDelta.dy)
        }
        let movementStrength = min(1, distance > 0 ? maxStep / max(1, followSpeed * CGFloat(deltaTime)) : 0)
        rig.update(deltaTime: deltaTime, velocity: lastDelta, movementStrength: movementStrength)
        updateDirectionalHeight()
        shadowNode.xScale = 1 - movementStrength * 0.06
        shadowNode.yScale = 1 - movementStrength * 0.10
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
                return .releaseProjectile
            }
            return .none
        }

        nextFireTimer -= deltaTime
        guard nextFireTimer <= 0, ammo > 0 else { return .none }

        ammo -= 1
        nextFireTimer = GameConfig.autoAttackTestEnabled
            ? GameConfig.autoAttackRepeatFireDelay
            : TimeInterval.random(in: GameConfig.enemyAttackIntervalRange)
        throwReleaseTimer = GameConfig.enemyThrowReleaseTime
        isThrowQueued = true
        rig.beginThrow()
        rig.setAmmoRatio(CGFloat(ammo) / CGFloat(GameConfig.maxAmmo))
        return .beganThrow
    }

    private func chooseBias() {
        let baseRange = GameConfig.mapSize.width * GameConfig.enemyHorizontalDriftRangeRatio
        lateralBias = CGFloat.random(in: -baseRange...baseRange)
        verticalBias = CGFloat.random(in: -GameConfig.enemyVerticalDrift...GameConfig.enemyVerticalDrift)
        chooseNewBias()
    }

    private func chooseNewBias() {
        decisionTimer = 0
        decisionDuration = TimeInterval.random(in: GameConfig.enemyDecisionDurationRange)
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
        projectileNode.isHidden = false
        hasReleasedProjectile = false
        setAmmoRatio(1)
    }

    func update(deltaTime: TimeInterval, velocity: CGVector, movementStrength: CGFloat) {
        if velocity.length > 1 {
            let facingAngle = atan2(velocity.dx, -velocity.dy)
            rootNode.eulerAngles.y = Float(facingAngle)
        }

        let clampedStrength = min(1, max(0, movementStrength))
        walkPhase += CGFloat(deltaTime) * (6.4 + clampedStrength * 3.2)
        throwTimeRemaining = max(0, throwTimeRemaining - deltaTime)
        let throwProgress = throwTimeRemaining > 0
            ? 1 - CGFloat(throwTimeRemaining / GameConfig.enemyThrowDuration)
            : 0

        let legSwing = sin(walkPhase) * 0.42 * clampedStrength
        let armSwing = sin(walkPhase) * 0.24 * clampedStrength
        let bodyBob = abs(sin(walkPhase)) * 0.08 * clampedStrength
        let throwWindup = easedPhase(progress: throwProgress, start: 0.0, end: 0.24)
        let throwRelease = easedPhase(progress: throwProgress, start: 0.24, end: 0.60)
        let throwFollowThrough = easedPhase(progress: throwProgress, start: 0.60, end: 1.0)
        let throwArm = throwWindup * 2.12 - throwRelease * 3.82 + throwFollowThrough * 0.40
        let torsoTwist = throwRelease * 0.54 - throwWindup * 0.30
        let torsoLean = throwWindup * 0.34 - throwRelease * 0.12

        if !hasReleasedProjectile, throwProgress >= CGFloat(GameConfig.enemyThrowReleaseTime / GameConfig.enemyThrowDuration) {
            projectileNode.isHidden = true
            hasReleasedProjectile = true
        }

        bodyNode.position.y = 0.68 + Float(bodyBob)
        torsoNode.eulerAngles.y = Float(torsoTwist)
        torsoNode.eulerAngles.z = Float(-torsoTwist * 0.18)
        bodyNode.eulerAngles.x = Float(torsoLean)
        leftLegPivot.eulerAngles.x = Float(-legSwing)
        rightLegPivot.eulerAngles.x = Float(legSwing)
        leftArmPivot.eulerAngles.x = Float(armSwing - throwRelease * 0.08)
        rightArmPivot.eulerAngles.x = Float(-0.28 - armSwing + throwArm)
        leftArmPivot.eulerAngles.z = Float(0.10 + throwRelease * 0.03)
        rightArmPivot.eulerAngles.y = Float(-0.34 - throwWindup * 1.12 + throwRelease * 0.34)
        rightArmPivot.eulerAngles.z = Float(-0.66 - throwWindup * 0.56 + throwRelease * 1.20 - throwFollowThrough * 0.34)
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
        cameraNode.position = SCNVector3(0, 3.26, 2.40)
        cameraNode.eulerAngles = SCNVector3(-0.71, 0, 0)
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
        projectileNode.position = SCNVector3(0.18, -0.10, 0.18)
        rightHandNode.addChildNode(projectileNode)

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
