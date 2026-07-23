import SceneKit
import SpriteKit
import Metal

final class PlayerNode: SKNode {
    static let menuPortraitImage: UIImage = {
        let portraitRig = PlayerFigureRig()
        portraitRig.resetPose()
        portraitRig.update(deltaTime: 0, facingAngle: 0, movementStrength: 0)
        return portraitRig.makePortrait()
    }()

    private let shadowNode = SKShapeNode(
        ellipseOf: CGSize(
            width: GameConfig.tileSize * 0.72,
            height: GameConfig.tileSize * 0.34
        )
    )
    private let groundIndicatorNode = SKNode()
    private let healthBarNode = SKNode()
    private let healthBarFillNode = SKShapeNode()
    private let modelNode = SK3DNode(viewportSize: GameConfig.playerModelViewportSize)
    private let figure = PlayerFigureRig()

    private(set) var velocity: CGVector = .zero
    private(set) var currentHP = GameConfig.playerMaxHP

    private var facingAngle: CGFloat = .pi
    private var targetFacingAngle: CGFloat = .pi
    private var isRateLimitedVelocityTransition = false
    private let debugFacingAngle = PlayerNode.loadDebugFacingAngle()

    override init() {
        super.init()

        configureGroundIndicator()
        configureHealthBar()

        shadowNode.position = CGPoint(x: 0, y: -28)
        shadowNode.fillColor = UIColor.black.withAlphaComponent(0.18)
        shadowNode.strokeColor = .clear
        shadowNode.zPosition = -1

        modelNode.scnScene = figure.scene
        modelNode.pointOfView = figure.cameraNode
        let displayScale = GameConfig.playerModelDisplaySize.width / GameConfig.playerModelViewportSize.width
        modelNode.xScale = displayScale * GameConfig.playerModelWidthScale
        modelNode.yScale = displayScale * GameConfig.playerModelHeightScale
        modelNode.position = CGPoint(x: 0, y: -8)

        addChild(groundIndicatorNode)
        addChild(shadowNode)
        addChild(modelNode)
        addChild(healthBarNode)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func reset() {
        velocity = .zero
        isRateLimitedVelocityTransition = false
        currentHP = GameConfig.playerMaxHP
        alpha = 1
        setScale(1)
        // Spawn facing toward the far side of the arena.
        facingAngle = debugFacingAngle ?? .pi
        targetFacingAngle = facingAngle
        figure.resetPose()
        figure.update(deltaTime: 0, facingAngle: facingAngle, movementStrength: 0)
        updateDirectionalHeight()
        updateHealthBar()
    }

    func applyMovement(input: CGVector, deltaTime: TimeInterval, mapRect: CGRect) {
        let movementInput = input.length > 0.05 ? input.normalized : .zero
        let facingInput = debugFacingAngle == nil ? movementInput : .zero

        if facingInput.length > 0.05 {
            updateFacing(with: facingInput, deltaTime: deltaTime)
        } else if let debugFacingAngle {
            facingAngle = debugFacingAngle
            targetFacingAngle = debugFacingAngle
        }

        updateVelocity(with: movementInput, deltaTime: deltaTime)
        let delta = velocity * CGFloat(deltaTime)
        let nextPosition = CGPoint(x: position.x + delta.dx, y: position.y + delta.dy)
        position = nextPosition.clamped(
            in: mapRect.insetBy(dx: GameConfig.playerCollisionRadius, dy: GameConfig.playerCollisionRadius)
        )

        let movementStrength = min(1, velocity.length / max(1, GameConfig.playerSpeed))
        figure.update(deltaTime: deltaTime, facingAngle: facingAngle, movementStrength: movementStrength)
        updateDirectionalHeight()
        shadowNode.xScale = 1 - movementStrength * 0.08
        shadowNode.yScale = 1 - movementStrength * 0.14
    }

    func takeDamage(_ damage: CGFloat) -> Bool {
        currentHP = max(0, currentHP - damage)
        updateHealthBar()

        removeAction(forKey: "hitFlash")
        let flash = SKAction.sequence([
            .group([
                .fadeAlpha(to: 0.55, duration: 0.04),
                .scale(to: 1.08, duration: 0.04)
            ]),
            .group([
                .fadeAlpha(to: 1.0, duration: 0.08),
                .scale(to: 1.0, duration: 0.08)
            ])
        ])
        run(flash, withKey: "hitFlash")

        return currentHP <= 0
    }

    private func configureGroundIndicator() {
        let size = GameConfig.playerGroundIndicatorSize

        let outer = SKShapeNode(ellipseOf: size)
        outer.fillColor = UIColor(red: 0.02, green: 0.11, blue: 0.18, alpha: 0.34)
        outer.strokeColor = UIColor(red: 0.10, green: 0.88, blue: 0.84, alpha: 0.92)
        outer.lineWidth = 2.4
        outer.glowWidth = 1.2

        let inner = SKShapeNode(
            ellipseOf: CGSize(width: size.width * 0.72, height: size.height * 0.68)
        )
        inner.fillColor = .clear
        inner.strokeColor = UIColor(red: 0.33, green: 0.55, blue: 0.98, alpha: 0.72)
        inner.lineWidth = 1.35

        groundIndicatorNode.position = CGPoint(
            x: 0,
            y: GameConfig.playerGroundIndicatorYOffset
        )
        groundIndicatorNode.zPosition = -2
        groundIndicatorNode.addChild(outer)
        groundIndicatorNode.addChild(inner)
    }

    private func configureHealthBar() {
        let size = GameConfig.playerHealthBarSize
        let backing = SKShapeNode(rectOf: size, cornerRadius: size.height * 0.48)
        backing.fillColor = UIColor(red: 0.025, green: 0.055, blue: 0.10, alpha: 0.94)
        backing.strokeColor = .clear

        let fillSize = GameConfig.playerHealthBarFillSize
        healthBarFillNode.path = CGPath(
            roundedRect: CGRect(
                x: -fillSize.width / 2,
                y: -fillSize.height / 2,
                width: fillSize.width,
                height: fillSize.height
            ),
            cornerWidth: fillSize.height * 0.48,
            cornerHeight: fillSize.height * 0.48,
            transform: nil
        )
        healthBarFillNode.fillColor = UIColor(red: 0.08, green: 0.86, blue: 0.82, alpha: 1)
        healthBarFillNode.strokeColor = .clear

        let topGlint = SKShapeNode(
            rectOf: CGSize(width: fillSize.width * 0.82, height: max(0.7, fillSize.height * 0.16)),
            cornerRadius: fillSize.height * 0.12
        )
        topGlint.position = CGPoint(x: 0, y: fillSize.height * 0.20)
        topGlint.fillColor = UIColor.white.withAlphaComponent(0.22)
        topGlint.strokeColor = .clear
        healthBarFillNode.addChild(topGlint)

        healthBarNode.position = CGPoint(x: 0, y: GameConfig.playerHealthBarYOffset)
        healthBarNode.zPosition = 4
        healthBarNode.addChild(backing)
        healthBarNode.addChild(healthBarFillNode)
    }

    private func updateHealthBar() {
        let ratio = min(1, max(0, currentHP / max(1, GameConfig.playerMaxHP)))
        let innerWidth = GameConfig.playerHealthBarFillSize.width
        healthBarFillNode.xScale = max(0.001, ratio)
        healthBarFillNode.position.x = -innerWidth * (1 - ratio) / 2

        if ratio <= 0.25 {
            healthBarFillNode.fillColor = UIColor(red: 0.98, green: 0.29, blue: 0.36, alpha: 1)
        } else if ratio <= 0.50 {
            healthBarFillNode.fillColor = UIColor(red: 1.00, green: 0.66, blue: 0.20, alpha: 1)
        } else {
            healthBarFillNode.fillColor = UIColor(red: 0.08, green: 0.86, blue: 0.82, alpha: 1)
        }
    }

    var hitCenterWorld: CGPoint {
        CGPoint(
            x: position.x,
            y: position.y + GameConfig.playerHitCenterYOffset
        )
    }

    /// Collision is a fixed circle on the gameplay plane. It deliberately
    /// ignores the projected head, limbs, facing angle and animation pose.
    /// BulletNode separately enforces the required projectile overlap.
    func containsHitPoint(_ worldPoint: CGPoint) -> Bool {
        let center = hitCenterWorld
        let deltaX = worldPoint.x - center.x
        let deltaY = worldPoint.y - center.y
        let radius = GameConfig.playerHitRadius
        return deltaX * deltaX + deltaY * deltaY <= radius * radius
    }

    private func updateVelocity(with input: CGVector, deltaTime: TimeInterval) {
        guard input != .zero else {
            let maximumChange =
                GameConfig.playerReleaseDeceleration * CGFloat(deltaTime)
            if velocity.length <= maximumChange {
                velocity = .zero
            } else {
                velocity = velocity + velocity.normalized * -maximumChange
            }
            isRateLimitedVelocityTransition = false
            return
        }

        let desiredVelocity = input * GameConfig.playerSpeed
        let difference = CGVector(
            dx: desiredVelocity.dx - velocity.dx,
            dy: desiredVelocity.dy - velocity.dy
        )

        if velocity.length < 0.001 {
            isRateLimitedVelocityTransition = true
        } else if !isRateLimitedVelocityTransition {
            let denominator = velocity.length * desiredVelocity.length
            if denominator > 0 {
                let dotProduct = velocity.dx * desiredVelocity.dx
                    + velocity.dy * desiredVelocity.dy
                let cosine = min(
                    1,
                    max(-1, dotProduct / denominator)
                )
                if acos(cosine) >= GameConfig.playerHardTurnThreshold {
                    isRateLimitedVelocityTransition = true
                }
            }
        }

        if !isRateLimitedVelocityTransition {
            let response = CGFloat(
                1 - exp(-deltaTime / GameConfig.playerSteeringResponseTime)
            )
            velocity = velocity + difference * response
            return
        }

        let maximumChange = GameConfig.playerMovementAcceleration * CGFloat(deltaTime)
        if difference.length <= maximumChange {
            velocity = desiredVelocity
            isRateLimitedVelocityTransition = false
        } else {
            velocity = velocity + difference.normalized * maximumChange
        }
    }

    private func updateFacing(with input: CGVector, deltaTime: TimeInterval) {
        targetFacingAngle = atan2(input.dx, -input.dy)
        let difference = atan2(
            sin(targetFacingAngle - facingAngle),
            cos(targetFacingAngle - facingAngle)
        )
        let maximumChange = GameConfig.playerFacingTurnRate * CGFloat(deltaTime)
        facingAngle += min(max(difference, -maximumChange), maximumChange)
    }

    private func updateDirectionalHeight() {
        // Perspective and the asymmetric model silhouette make its apparent
        // height vary by facing direction. These factors normalize the measured
        // ear-to-foot heights (toward 6, side 8, away-diagonal 7, away 6.5 mm)
        // to 6.5 mm. Interpolation prevents visible size steps while turning.
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
        let displayScale = GameConfig.playerModelDisplaySize.width
            / GameConfig.playerModelViewportSize.width
        modelNode.yScale = displayScale * GameConfig.playerModelHeightScale * directionalScale

        // The rear silhouette's visual foot anchor sits slightly above the
        // rig origin. Ease it toward the player so the feet remain centered
        // in the ground indicator while turning toward the far side.
        let rearAlignment = (1 - cos(angleFromToward)) / 2
        modelNode.position.y = -8 - 2.5 * rearAlignment
    }

    private static func loadDebugFacingAngle() -> CGFloat? {
        guard
            let rawValue = ProcessInfo.processInfo.environment["BULLETDODGE_DEBUG_FACING"],
            let index = Int(rawValue)
        else {
            return nil
        }

        return (CGFloat(min(max(index, 0), 23)) / 24) * .pi * 2
    }

}

private final class PlayerFigureRig {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let rootNode = SCNNode()
    private let bodyNode = SCNNode()
    private let hoodNode = SCNNode()
    private let headNode = SCNNode()
    private let faceNode = SCNNode()
    private let bandNode = SCNNode()
    private let gemNode = SCNNode()

    private let leftArmPivot = SCNNode()
    private let rightArmPivot = SCNNode()
    private let leftLegPivot = SCNNode()
    private let rightLegPivot = SCNNode()
    private let leftHandNode = SCNNode()
    private let rightHandNode = SCNNode()
    private let leftFootNode = SCNNode()
    private let rightFootNode = SCNNode()

    private var walkPhase: CGFloat = 0
    private var armSpinPhase: CGFloat = 0
    private lazy var hitMaskRenderer: SCNRenderer? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        return renderer
    }()

    init() {
        scene.background.contents = UIColor.clear
        configureCamera()
        configureLights()
        configureFigure()
    }

    func resetPose() {
        walkPhase = 0
        armSpinPhase = 0
        rootNode.eulerAngles = SCNVector3(0, 0, 0)
        rootNode.position = SCNVector3(0, -0.36, 0)
        bodyNode.eulerAngles = SCNVector3(0, 0, 0)
        leftArmPivot.eulerAngles = SCNVector3(0, 0, 0)
        rightArmPivot.eulerAngles = SCNVector3(0, 0, 0)
        leftLegPivot.eulerAngles = SCNVector3(0, 0, 0)
        rightLegPivot.eulerAngles = SCNVector3(0, 0, 0)
    }

    func update(deltaTime: TimeInterval, facingAngle: CGFloat, movementStrength: CGFloat) {
        let targetYaw = Float(facingAngle)
        rootNode.eulerAngles.y = targetYaw

        let clampedStrength = min(1, max(0, movementStrength))
        if clampedStrength > 0.05 {
            walkPhase += CGFloat(deltaTime) * (7.5 + clampedStrength * 4.5)
        } else {
            walkPhase += CGFloat(deltaTime) * 2
        }
        armSpinPhase += CGFloat(deltaTime) * (4.35 + clampedStrength * 0.45)

        let armSwing = sin(walkPhase) * 0.62 * clampedStrength
        let legSwing = sin(walkPhase) * 0.72 * clampedStrength
        let bodyBob = abs(sin(walkPhase)) * 0.10 * clampedStrength
        let bodyRoll = sin(walkPhase) * 0.06 * clampedStrength

        bodyNode.position.y = 1.20 + Float(bodyBob)
        bodyNode.eulerAngles.z = Float(bodyRoll)

        leftArmPivot.eulerAngles.x = Float(armSwing * 0.70)
        // Rotate around the local X axis so the hand travels forward, upward,
        // backward and downward in a genuinely vertical overhand circle.
        // Rotating around Z would sweep sideways across the body instead.
        rightArmPivot.eulerAngles.x = Float(armSpinPhase)
        rightArmPivot.eulerAngles.y = 0
        rightArmPivot.eulerAngles.z = 0
        leftLegPivot.eulerAngles.x = Float(-legSwing)
        rightLegPivot.eulerAngles.x = Float(legSwing)

    }

    func makePortrait() -> UIImage {
        guard let renderer = hitMaskRenderer else { return UIImage() }
        SCNTransaction.flush()
        let image = renderer.snapshot(
            atTime: 0,
            with: GameConfig.playerModelViewportSize,
            antialiasingMode: .multisampling4X
        )
        return cropTransparentPadding(from: image)
    }

    private func cropTransparentPadding(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { storage in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard minX <= maxX, minY <= maxY else { return image }
        let padding = 8
        let cropRect = CGRect(
            x: max(0, minX - padding),
            y: max(0, minY - padding),
            width: min(width - 1, maxX + padding) - max(0, minX - padding) + 1,
            height: min(height - 1, maxY + padding) - max(0, minY - padding) + 1
        )
        guard let croppedImage = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: croppedImage, scale: image.scale, orientation: .up)
    }

    private func configureCamera() {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        camera.fieldOfView = 44
        camera.zNear = 0.01
        camera.zFar = 20
        cameraNode.camera = camera
        // Five degrees steeper than the previous view. Move along the same
        // camera orbit so the character's screen-space size stays stable.
        cameraNode.position = SCNVector3(0, 3.636, 2.373)
        cameraNode.eulerAngles = SCNVector3(-0.8073, 0, 0)
        scene.rootNode.addChildNode(cameraNode)
    }

    private func configureLights() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 620
        ambient.light?.color = UIColor(white: 0.88, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 650
        key.light?.color = UIColor(white: 0.95, alpha: 1)
        key.position = SCNVector3(1.6, 5.2, 2.2)
        scene.rootNode.addChildNode(key)

        // A restrained back light separates the black silhouette from the map
        // without creating the wet/plastic gloss of the previous version.
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .omni
        rim.light?.intensity = 150
        rim.light?.color = UIColor(red: 0.42, green: 0.53, blue: 0.68, alpha: 1)
        rim.position = SCNVector3(-2.4, 3.4, -2.2)
        scene.rootNode.addChildNode(rim)
    }

    private func configureFigure() {
        scene.rootNode.addChildNode(rootNode)
        rootNode.position = SCNVector3(0, -0.36, 0)

        // Silverback proportions from the supplied reference: a forward-set
        // head, high sloping shoulders, tapered waist, very long heavy arms and
        // short planted legs. The body remains in the calibrated 6.5 x 4.5 mm
        // envelope; the visual-only flail is deliberately outside that box.
        let blackFur = UIColor(red: 0.335, green: 0.345, blue: 0.365, alpha: 1)
        let liftedFur = UIColor(red: 0.455, green: 0.465, blue: 0.485, alpha: 1)
        let bareSkin = UIColor(red: 0.500, green: 0.495, blue: 0.480, alpha: 1)
        let chestSkin = UIColor(red: 0.555, green: 0.550, blue: 0.525, alpha: 1)

        bodyNode.geometry = SCNCone(topRadius: 0.43, bottomRadius: 0.27, height: 0.96)
        bodyNode.geometry?.firstMaterial = material(color: blackFur)
        // Extra depth is only exposed when the rig turns sideways, making the
        // side silhouette fuller without widening the front view.
        bodyNode.scale = SCNVector3(1.06, 0.96, 1.02)
        bodyNode.position = SCNVector3(0, 1.20, 0)
        rootNode.addChildNode(bodyNode)

        for side: Float in [-1, 1] {
            let shoulder = SCNNode(geometry: SCNSphere(radius: 0.30))
            shoulder.geometry?.firstMaterial = material(color: liftedFur)
            shoulder.scale = SCNVector3(1.12, 1.08, 0.90)
            shoulder.position = SCNVector3(0.31 * side, 0.28, 0)
            bodyNode.addChildNode(shoulder)
        }

        headNode.geometry = SCNSphere(radius: 0.35)
        headNode.geometry?.firstMaterial = material(color: blackFur)
        headNode.scale = SCNVector3(0.96, 1.06, 0.92)
        headNode.position = SCNVector3(0, 0.69, 0.06)
        bodyNode.addChildNode(headNode)

        let crown = SCNNode(geometry: SCNSphere(radius: 0.25))
        crown.geometry?.firstMaterial = material(color: liftedFur)
        crown.scale = SCNVector3(0.84, 1.12, 0.82)
        crown.position = SCNVector3(0, 0.25, -0.035)
        headNode.addChildNode(crown)

        let brow = SCNNode(geometry: SCNBox(width: 0.48, height: 0.12, length: 0.13, chamferRadius: 0.045))
        brow.geometry?.firstMaterial = material(color: liftedFur)
        brow.position = SCNVector3(0, 0.055, 0.33)
        headNode.addChildNode(brow)

        let muzzle = SCNNode(geometry: SCNSphere(radius: 0.225))
        muzzle.geometry?.firstMaterial = material(color: bareSkin)
        muzzle.scale = SCNVector3(1.18, 0.72, 0.72)
        muzzle.position = SCNVector3(0, -0.13, 0.355)
        headNode.addChildNode(muzzle)

        let nose = SCNNode(geometry: SCNSphere(radius: 0.082))
        nose.geometry?.firstMaterial = material(color: UIColor(white: 0.035, alpha: 1))
        nose.scale = SCNVector3(1.35, 0.68, 0.62)
        nose.position = SCNVector3(0, -0.055, 0.495)
        headNode.addChildNode(nose)

        for side: Float in [-1, 1] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.026))
            eye.geometry?.firstMaterial = material(color: UIColor(red: 0.20, green: 0.13, blue: 0.07, alpha: 1))
            eye.position = SCNVector3(0.125 * side, 0.035, 0.405)
            headNode.addChildNode(eye)

            let ear = SCNNode(geometry: SCNTorus(ringRadius: 0.060, pipeRadius: 0.022))
            ear.geometry?.firstMaterial = material(color: bareSkin)
            ear.eulerAngles.x = .pi / 2
            ear.position = SCNVector3(0.33 * side, -0.005, 0.015)
            headNode.addChildNode(ear)

            let armPivot = side < 0 ? leftArmPivot : rightArmPivot
            armPivot.position = SCNVector3(0.38 * side, 0.28, 0.015)
            bodyNode.addChildNode(armPivot)

            let upperArm = SCNNode(geometry: SCNCapsule(capRadius: 0.165, height: 0.56))
            upperArm.geometry?.firstMaterial = material(color: liftedFur)
            upperArm.scale = SCNVector3(1.04, 1.0, 0.94)
            upperArm.position = SCNVector3(0.045 * side, -0.20, 0.025)
            upperArm.eulerAngles.z = side < 0 ? 0.13 : -0.13
            armPivot.addChildNode(upperArm)

            let forearm = SCNNode(geometry: SCNCapsule(capRadius: 0.175, height: 0.60))
            forearm.geometry?.firstMaterial = material(color: liftedFur)
            forearm.scale = SCNVector3(1.08, 1.0, 0.96)
            forearm.position = SCNVector3(0.075 * side, -0.57, 0.055)
            forearm.eulerAngles.z = side < 0 ? -0.07 : 0.07
            armPivot.addChildNode(forearm)

            let paw = side < 0 ? leftHandNode : rightHandNode
            paw.geometry = SCNSphere(radius: 0.175)
            paw.geometry?.firstMaterial = material(color: bareSkin)
            paw.scale = SCNVector3(0.90, 1.08, 0.90)
            paw.position = SCNVector3(0.055 * side, -0.88, 0.12)
            armPivot.addChildNode(paw)

            let legPivot = side < 0 ? leftLegPivot : rightLegPivot
            legPivot.position = SCNVector3(0.19 * side, -0.39, -0.02)
            bodyNode.addChildNode(legPivot)

            let leg = SCNNode(geometry: SCNCapsule(capRadius: 0.155, height: 0.42))
            leg.geometry?.firstMaterial = material(color: blackFur)
            leg.position = SCNVector3(0, -0.18, 0.015)
            legPivot.addChildNode(leg)

            let foot = side < 0 ? leftFootNode : rightFootNode
            foot.geometry = SCNSphere(radius: 0.18)
            foot.geometry?.firstMaterial = material(color: bareSkin)
            foot.scale = SCNVector3(1.12, 0.52, 1.45)
            foot.position = SCNVector3(0.02 * side, -0.45, 0.15)
            legPivot.addChildNode(foot)
        }

        for side: Float in [-1, 1] {
            let pectoral = SCNNode(geometry: SCNSphere(radius: 0.23))
            pectoral.geometry?.firstMaterial = material(color: chestSkin)
            pectoral.scale = SCNVector3(1.0, 0.72, 0.26)
            pectoral.position = SCNVector3(0.17 * side, 0.15, 0.38)
            bodyNode.addChildNode(pectoral)
        }
        for row in 0..<2 {
            for side: Float in [-1, 1] {
                let abdominal = SCNNode(geometry: SCNSphere(radius: 0.135))
                abdominal.geometry?.firstMaterial = material(color: chestSkin)
                abdominal.scale = SCNVector3(0.78, 0.58, 0.22)
                abdominal.position = SCNVector3(0.105 * side, -0.08 - Float(row) * 0.16, 0.33)
                bodyNode.addChildNode(abdominal)
            }
        }

    }

    private func configurePillarFigure() {
        scene.rootNode.addChildNode(rootNode)
        rootNode.position = SCNVector3(0, -0.36, 0)

        // Original dusk-badger creature. The head and torso are separate, broad
        // round volumes so their outline reads clearly without a thin neck.
        bodyNode.geometry = SCNCapsule(capRadius: 0.44, height: 1.75)
        bodyNode.geometry?.firstMaterial = material(color: UIColor(red: 0.075, green: 0.085, blue: 0.105, alpha: 1))
        bodyNode.position = SCNVector3(0, 1.20, 0)
        rootNode.addChildNode(bodyNode)

        headNode.geometry = SCNSphere(radius: 0.46)
        headNode.geometry?.firstMaterial = material(color: UIColor(red: 0.085, green: 0.095, blue: 0.115, alpha: 1))
        headNode.position = SCNVector3(0, 0.72, 0)
        bodyNode.addChildNode(headNode)

        let browMark = SCNNode(geometry: SCNBox(width: 0.54, height: 0.13, length: 0.045, chamferRadius: 0.05))
        browMark.geometry?.firstMaterial = material(color: UIColor(red: 0.52, green: 0.48, blue: 0.38, alpha: 1))
        browMark.position = SCNVector3(0, -0.05, 0.43)
        headNode.addChildNode(browMark)

        // The muzzle projects beyond the round torso. From the side it supplies
        // the same visible width that the forepaws supply from the front.
        let muzzle = SCNNode(geometry: SCNCapsule(capRadius: 0.10, height: 0.40))
        muzzle.geometry?.firstMaterial = material(color: UIColor(red: 0.57, green: 0.52, blue: 0.42, alpha: 1))
        muzzle.eulerAngles.x = .pi / 2
        muzzle.position = SCNVector3(0, -0.21, 0.42)
        headNode.addChildNode(muzzle)

        let nose = SCNNode(geometry: SCNSphere(radius: 0.042))
        nose.geometry?.firstMaterial = material(color: UIColor(red: 0.055, green: 0.035, blue: 0.035, alpha: 1))
        nose.position = SCNVector3(0, -0.21, 0.635)
        headNode.addChildNode(nose)

        for side: Float in [-1, 1] {
            let flankMark = SCNNode(geometry: SCNSphere(radius: 0.28))
            flankMark.geometry?.firstMaterial = material(color: UIColor(red: 0.24, green: 0.27, blue: 0.28, alpha: 1))
            flankMark.scale = SCNVector3(0.06, 1.25, 0.62)
            flankMark.position = SCNVector3(0.438 * side, -0.16, 0)
            bodyNode.addChildNode(flankMark)

            let eye = SCNNode(geometry: SCNSphere(radius: 0.032))
            eye.geometry?.firstMaterial = material(
                color: UIColor(red: 0.96, green: 0.50, blue: 0.10, alpha: 1),
                emission: UIColor(red: 0.28, green: 0.07, blue: 0.01, alpha: 0.18)
            )
            eye.position = SCNVector3(0.15 * side, -0.04, 0.44)
            headNode.addChildNode(eye)

            let ear = SCNNode(geometry: SCNCone(topRadius: 0.015, bottomRadius: 0.105, height: 0.27))
            ear.geometry?.firstMaterial = material(color: UIColor(red: 0.18, green: 0.17, blue: 0.17, alpha: 1))
            ear.position = SCNVector3(0.28 * side, 0.43, 0)
            ear.eulerAngles.z = side < 0 ? -0.18 : 0.18
            headNode.addChildNode(ear)

            let forePaw = SCNNode(geometry: SCNCapsule(capRadius: 0.075, height: 0.42))
            forePaw.geometry?.firstMaterial = material(color: UIColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1))
            forePaw.position = SCNVector3(0.25 * side, 0.02, 0.19)
            forePaw.eulerAngles.z = side < 0 ? 0.05 : -0.05
            bodyNode.addChildNode(forePaw)

            let foot = side < 0 ? leftFootNode : rightFootNode
            foot.geometry = SCNSphere(radius: 0.17)
            foot.geometry?.firstMaterial = material(color: UIColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1))
            foot.scale = SCNVector3(1.0, 0.58, 1.0)
            foot.position = SCNVector3(0.20 * side, -1.03, 0.02)
            bodyNode.addChildNode(foot)
        }

        let chestFur = SCNNode(geometry: SCNSphere(radius: 0.31))
        chestFur.geometry?.firstMaterial = material(color: UIColor(red: 0.25, green: 0.28, blue: 0.29, alpha: 1))
        chestFur.scale = SCNVector3(0.92, 1.22, 0.14)
        chestFur.position = SCNVector3(0, -0.16, 0.335)
        bodyNode.addChildNode(chestFur)

        let scarf = SCNNode(geometry: SCNTorus(ringRadius: 0.29, pipeRadius: 0.045))
        scarf.geometry?.firstMaterial = material(color: UIColor(red: 0.47, green: 0.045, blue: 0.065, alpha: 1))
        scarf.eulerAngles.x = .pi / 2
        scarf.position = SCNVector3(0, 0.31, 0)
        bodyNode.addChildNode(scarf)
    }

    private func configureShadowFigure() {
        scene.rootNode.addChildNode(rootNode)
        rootNode.position = SCNVector3(0, -0.36, 0)

        // A single continuous, non-human silhouette: no oversized head, thin
        // neck, toy-like ball joints or narrow feet. Its outer edge remains at
        // x = +/-0.38 from crown to both split foot tips.
        let silhouettePath = UIBezierPath()
        silhouettePath.move(to: CGPoint(x: -0.38, y: -0.62))
        silhouettePath.addLine(to: CGPoint(x: -0.38, y: 1.12))
        silhouettePath.addCurve(
            to: CGPoint(x: -0.20, y: 1.46),
            controlPoint1: CGPoint(x: -0.38, y: 1.30),
            controlPoint2: CGPoint(x: -0.31, y: 1.42)
        )
        silhouettePath.addCurve(
            to: CGPoint(x: 0.20, y: 1.46),
            controlPoint1: CGPoint(x: -0.10, y: 1.54),
            controlPoint2: CGPoint(x: 0.10, y: 1.54)
        )
        silhouettePath.addCurve(
            to: CGPoint(x: 0.38, y: 1.12),
            controlPoint1: CGPoint(x: 0.31, y: 1.42),
            controlPoint2: CGPoint(x: 0.38, y: 1.30)
        )
        silhouettePath.addLine(to: CGPoint(x: 0.38, y: -0.62))
        silhouettePath.addLine(to: CGPoint(x: 0.08, y: -0.62))
        silhouettePath.addLine(to: CGPoint(x: 0, y: -0.45))
        silhouettePath.addLine(to: CGPoint(x: -0.08, y: -0.62))
        silhouettePath.close()

        let silhouette = SCNShape(path: silhouettePath, extrusionDepth: 0.30)
        silhouette.chamferRadius = 0.035
        bodyNode.geometry = silhouette
        bodyNode.geometry?.materials = [
            material(color: UIColor(red: 0.035, green: 0.055, blue: 0.095, alpha: 1)),
            material(color: UIColor(red: 0.08, green: 0.11, blue: 0.18, alpha: 1))
        ]
        bodyNode.position = SCNVector3(0, 0.78, 0)
        rootNode.addChildNode(bodyNode)

        let mantlePath = UIBezierPath()
        mantlePath.move(to: CGPoint(x: -0.29, y: -0.38))
        mantlePath.addCurve(
            to: CGPoint(x: -0.25, y: 0.72),
            controlPoint1: CGPoint(x: -0.34, y: 0.02),
            controlPoint2: CGPoint(x: -0.22, y: 0.38)
        )
        mantlePath.addCurve(
            to: CGPoint(x: 0, y: 0.84),
            controlPoint1: CGPoint(x: -0.18, y: 0.80),
            controlPoint2: CGPoint(x: -0.08, y: 0.85)
        )
        mantlePath.addCurve(
            to: CGPoint(x: 0.25, y: 0.72),
            controlPoint1: CGPoint(x: 0.08, y: 0.85),
            controlPoint2: CGPoint(x: 0.18, y: 0.80)
        )
        mantlePath.addCurve(
            to: CGPoint(x: 0.29, y: -0.38),
            controlPoint1: CGPoint(x: 0.22, y: 0.38),
            controlPoint2: CGPoint(x: 0.34, y: 0.02)
        )
        mantlePath.addCurve(
            to: CGPoint(x: 0, y: -0.27),
            controlPoint1: CGPoint(x: 0.20, y: -0.45),
            controlPoint2: CGPoint(x: 0.08, y: -0.24)
        )
        mantlePath.addCurve(
            to: CGPoint(x: -0.29, y: -0.38),
            controlPoint1: CGPoint(x: -0.08, y: -0.24),
            controlPoint2: CGPoint(x: -0.20, y: -0.45)
        )
        mantlePath.close()
        let mantle = SCNNode(geometry: SCNShape(path: mantlePath, extrusionDepth: 0.035))
        mantle.geometry?.firstMaterial = material(color: UIColor(red: 0.07, green: 0.16, blue: 0.25, alpha: 1))
        mantle.position = SCNVector3(0, 0, 0.17)
        bodyNode.addChildNode(mantle)

        let faceVoid = SCNNode(geometry: SCNSphere(radius: 0.29))
        faceVoid.geometry?.firstMaterial = material(color: UIColor(red: 0.015, green: 0.018, blue: 0.025, alpha: 1))
        faceVoid.scale = SCNVector3(1.0, 0.42, 0.20)
        faceVoid.position = SCNVector3(0, 1.10, 0.19)
        bodyNode.addChildNode(faceVoid)

        for side: Float in [-1, 1] {
            let eye = SCNNode(geometry: SCNBox(width: 0.12, height: 0.035, length: 0.025, chamferRadius: 0.012))
            eye.geometry?.firstMaterial = material(
                color: UIColor(red: 0.95, green: 0.42, blue: 0.10, alpha: 1),
                emission: UIColor(red: 0.30, green: 0.07, blue: 0.01, alpha: 0.22)
            )
            eye.position = SCNVector3(0.15 * side, 0, 0.065)
            eye.eulerAngles.z = side < 0 ? -0.08 : 0.08
            faceVoid.addChildNode(eye)
        }

        let diagonalSash = SCNNode(geometry: SCNBox(width: 0.70, height: 0.085, length: 0.055, chamferRadius: 0.025))
        diagonalSash.geometry?.firstMaterial = material(color: UIColor(red: 0.42, green: 0.045, blue: 0.075, alpha: 1))
        diagonalSash.position = SCNVector3(0, 0.26, 0.205)
        diagonalSash.eulerAngles.z = -0.24
        bodyNode.addChildNode(diagonalSash)

        let clasp = SCNNode(geometry: SCNOctahedronGeometry(radius: 0.085))
        clasp.geometry?.firstMaterial = material(color: UIColor(red: 0.66, green: 0.42, blue: 0.12, alpha: 1))
        clasp.position = SCNVector3(0.20, 0.21, 0.255)
        bodyNode.addChildNode(clasp)
    }

    private func configureLegacyFigure() {
        scene.rootNode.addChildNode(rootNode)
        rootNode.position = SCNVector3(0, -0.36, 0)

        // Player: an original masked wanderer made only from cloth and leather.
        // Hood, shoulders, coat, arms and boots share an almost straight 0.76-wide silhouette.
        bodyNode.geometry = SCNCapsule(capRadius: 0.34, height: 0.96)
        bodyNode.geometry?.firstMaterial = material(color: UIColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1))
        bodyNode.position = SCNVector3(0, 0.78, 0)
        rootNode.addChildNode(bodyNode)

        let tunic = SCNNode(geometry: SCNBox(width: 0.76, height: 0.58, length: 0.30, chamferRadius: 0.12))
        tunic.geometry?.firstMaterial = material(color: UIColor(red: 0.10, green: 0.20, blue: 0.29, alpha: 1))
        tunic.position = SCNVector3(0, -0.02, 0.20)
        bodyNode.addChildNode(tunic)

        let shoulderCape = SCNNode(geometry: SCNBox(width: 0.76, height: 0.16, length: 0.34, chamferRadius: 0.07))
        shoulderCape.geometry?.firstMaterial = material(color: UIColor(red: 0.20, green: 0.07, blue: 0.10, alpha: 1))
        shoulderCape.position = SCNVector3(0, 0.33, 0.10)
        bodyNode.addChildNode(shoulderCape)

        let collar = SCNNode(geometry: SCNTorus(ringRadius: 0.28, pipeRadius: 0.075))
        collar.geometry?.firstMaterial = material(color: UIColor(red: 0.48, green: 0.06, blue: 0.09, alpha: 1))
        collar.eulerAngles.x = .pi / 2
        collar.position = SCNVector3(0, 0.45, 0.10)
        bodyNode.addChildNode(collar)

        hoodNode.geometry = SCNSphere(radius: 0.35)
        hoodNode.geometry?.firstMaterial = material(color: UIColor(red: 0.16, green: 0.06, blue: 0.09, alpha: 1))
        hoodNode.scale = SCNVector3(1.0, 1.02, 1.02)
        hoodNode.position = SCNVector3(0, 1.25, 0.00)
        bodyNode.addChildNode(hoodNode)

        headNode.geometry = SCNSphere(radius: 0.28)
        headNode.geometry?.firstMaterial = material(color: UIColor(red: 0.48, green: 0.32, blue: 0.24, alpha: 1))
        headNode.scale = SCNVector3(1.02, 1.02, 1.04)
        headNode.position = SCNVector3(0, 1.22, 0.18)
        bodyNode.addChildNode(headNode)

        faceNode.geometry = SCNBox(width: 0.42, height: 0.13, length: 0.08, chamferRadius: 0.05)
        faceNode.geometry?.firstMaterial = material(color: UIColor(red: 0.24, green: 0.07, blue: 0.09, alpha: 1))
        faceNode.eulerAngles.z = .pi / 2
        faceNode.eulerAngles.z = 0
        faceNode.position = SCNVector3(0, -0.08, 0.26)
        headNode.addChildNode(faceNode)

        for offset in [-0.08, 0.08] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.026))
            eye.geometry?.firstMaterial = material(
                color: UIColor(red: 0.96, green: 0.48, blue: 0.12, alpha: 1),
                emission: UIColor(red: 0.25, green: 0.06, blue: 0.01, alpha: 0.16)
            )
            eye.position = SCNVector3(Float(offset), 0.045, 0.28)
            headNode.addChildNode(eye)
        }

        let hoodFold = SCNNode(geometry: SCNCone(topRadius: 0.025, bottomRadius: 0.10, height: 0.22))
        hoodFold.geometry?.firstMaterial = material(color: UIColor(red: 0.12, green: 0.05, blue: 0.08, alpha: 1))
        hoodFold.position = SCNVector3(0, 0.29, -0.03)
        headNode.addChildNode(hoodFold)

        bandNode.geometry = SCNBox(width: 0.74, height: 0.10, length: 0.34, chamferRadius: 0.04)
        bandNode.geometry?.firstMaterial = material(color: UIColor(red: 0.40, green: 0.05, blue: 0.07, alpha: 1))
        bandNode.position = SCNVector3(0, -0.18, 0.12)
        bodyNode.addChildNode(bandNode)

        gemNode.geometry = SCNOctahedronGeometry(radius: 0.10)
        gemNode.geometry?.firstMaterial = material(color: UIColor(red: 0.74, green: 0.48, blue: 0.14, alpha: 1))
        gemNode.position = SCNVector3(0, -0.16, 0.32)
        bodyNode.addChildNode(gemNode)

        let backCape = SCNNode(geometry: SCNBox(width: 0.72, height: 0.62, length: 0.08, chamferRadius: 0.05))
        backCape.geometry?.firstMaterial = material(color: UIColor(red: 0.07, green: 0.10, blue: 0.16, alpha: 1))
        backCape.position = SCNVector3(0, -0.08, -0.27)
        bodyNode.addChildNode(backCape)

        let scabbard = SCNNode(geometry: SCNBox(width: 0.09, height: 0.62, length: 0.08, chamferRadius: 0.035))
        scabbard.geometry?.firstMaterial = material(color: UIColor(red: 0.20, green: 0.10, blue: 0.07, alpha: 1))
        scabbard.position = SCNVector3(-0.10, 0.02, -0.33)
        scabbard.eulerAngles.z = 0.40
        bodyNode.addChildNode(scabbard)

        let swordHilt = SCNNode(geometry: SCNBox(width: 0.19, height: 0.055, length: 0.08, chamferRadius: 0.02))
        swordHilt.geometry?.firstMaterial = material(color: UIColor(red: 0.58, green: 0.38, blue: 0.13, alpha: 1))
        swordHilt.position = SCNVector3(0, 0.34, 0)
        scabbard.addChildNode(swordHilt)

        configureArm(pivot: leftArmPivot, side: -1)
        configureArm(pivot: rightArmPivot, side: 1)
        configureLeg(pivot: leftLegPivot, side: -1)
        configureLeg(pivot: rightLegPivot, side: 1)
    }

    private func configureArm(pivot: SCNNode, side: Float) {
        pivot.position = SCNVector3(0.25 * side, 0.32, 0.10)
        bodyNode.addChildNode(pivot)

        let arm = SCNNode(geometry: SCNCapsule(capRadius: 0.095, height: 0.44))
        arm.geometry?.firstMaterial = material(color: UIColor(red: 0.10, green: 0.18, blue: 0.26, alpha: 1))
        arm.position = SCNVector3(0.02 * side, -0.18, 0)
        arm.eulerAngles.z = side < 0 ? 0.08 : -0.08
        pivot.addChildNode(arm)

        let cuff = SCNNode(geometry: SCNTorus(ringRadius: 0.09, pipeRadius: 0.025))
        cuff.geometry?.firstMaterial = material(color: UIColor(red: 0.43, green: 0.06, blue: 0.08, alpha: 1))
        cuff.eulerAngles.x = .pi / 2
        cuff.position = SCNVector3(0.03 * side, -0.31, 0)
        pivot.addChildNode(cuff)

        let hand = side < 0 ? leftHandNode : rightHandNode
        hand.geometry = SCNSphere(radius: 0.10)
        hand.geometry?.firstMaterial = material(color: UIColor(red: 0.20, green: 0.21, blue: 0.24, alpha: 1))
        hand.position = SCNVector3(0.04 * side, -0.37, 0.03)
        pivot.addChildNode(hand)
    }

    private func configureLeg(pivot: SCNNode, side: Float) {
        pivot.position = SCNVector3(0.21 * side, -0.12, 0)
        bodyNode.addChildNode(pivot)

        let leg = SCNNode(geometry: SCNCapsule(capRadius: 0.12, height: 0.46))
        leg.geometry?.firstMaterial = material(color: UIColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1))
        leg.position = SCNVector3(0, -0.20, 0)
        pivot.addChildNode(leg)

        let foot = side < 0 ? leftFootNode : rightFootNode
        foot.geometry = SCNBox(width: 0.34, height: 0.15, length: 0.32, chamferRadius: 0.07)
        foot.geometry?.firstMaterial = material(color: UIColor(red: 0.14, green: 0.18, blue: 0.24, alpha: 1))
        foot.position = SCNVector3(0, -0.45, 0.08)
        pivot.addChildNode(foot)

        let sole = SCNNode(geometry: SCNBox(width: 0.34, height: 0.035, length: 0.32, chamferRadius: 0.02))
        sole.geometry?.firstMaterial = material(color: UIColor(red: 0.32, green: 0.05, blue: 0.07, alpha: 1))
        sole.position = SCNVector3(0, -0.06, 0)
        foot.addChildNode(sole)
    }

    private func material(color: UIColor, emission: UIColor = .black) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = emission
        material.specular.contents = UIColor.black
        material.lightingModel = .lambert
        material.roughness.contents = 1.0
        material.metalness.contents = 0.0
        material.fresnelExponent = 0
        return material
    }

}

private final class SCNOctahedronGeometry: SCNGeometry {
    convenience init(radius: CGFloat) {
        let r = Float(radius)
        let vertices: [SCNVector3] = [
            SCNVector3(0, r, 0),
            SCNVector3(r, 0, 0),
            SCNVector3(0, 0, r),
            SCNVector3(-r, 0, 0),
            SCNVector3(0, 0, -r),
            SCNVector3(0, -r, 0)
        ]
        let source = SCNGeometrySource(vertices: vertices)
        let indices: [Int32] = [
            0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 1,
            5, 2, 1, 5, 3, 2, 5, 4, 3, 5, 1, 4
        ]
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        self.init(sources: [source], elements: [element])
    }
}
