import SceneKit
import SpriteKit
import Metal

final class PlayerNode: SKNode {
    private let shadowNode = SKShapeNode(
        ellipseOf: CGSize(
            width: GameConfig.tileSize * 0.72,
            height: GameConfig.tileSize * 0.34
        )
    )
    private let modelNode = SK3DNode(viewportSize: GameConfig.playerModelViewportSize)
    private let figure = PlayerFigureRig()
    private var hitMasks: [Int: PlayerAlphaHitMask] = [:]

    private(set) var velocity: CGVector = .zero
    private(set) var currentHP = GameConfig.playerMaxHP

    private var facingAngle: CGFloat = 0
    private let debugFacingAngle = PlayerNode.loadDebugFacingAngle()

    override init() {
        super.init()

        shadowNode.position = CGPoint(x: 0, y: -28)
        shadowNode.fillColor = UIColor.black.withAlphaComponent(0.18)
        shadowNode.strokeColor = .clear

        modelNode.scnScene = figure.scene
        modelNode.pointOfView = figure.cameraNode
        let displayScale = GameConfig.playerModelDisplaySize.width / GameConfig.playerModelViewportSize.width
        modelNode.xScale = displayScale * GameConfig.playerModelWidthScale
        modelNode.yScale = displayScale * GameConfig.playerModelHeightScale
        modelNode.position = CGPoint(x: 0, y: -4)

        addChild(shadowNode)
        addChild(modelNode)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func reset() {
        velocity = .zero
        currentHP = GameConfig.playerMaxHP
        alpha = 1
        setScale(1)
        facingAngle = debugFacingAngle ?? 0
        figure.resetPose()
        figure.update(deltaTime: 0, facingAngle: facingAngle, movementStrength: 0)
        updateDirectionalHeight()
    }

    func applyMovement(input: CGVector, deltaTime: TimeInterval, mapRect: CGRect) {
        let movementInput = input.length > 0.05 ? input.normalized : .zero
        let facingInput = debugFacingAngle == nil ? movementInput : .zero

        if facingInput.length > 0.05 {
            updateFacing(with: facingInput)
        } else if let debugFacingAngle {
            facingAngle = debugFacingAngle
        }

        velocity = movementInput * GameConfig.playerSpeed
        let delta = velocity * CGFloat(deltaTime)
        let nextPosition = CGPoint(x: position.x + delta.dx, y: position.y + delta.dy)
        position = nextPosition.clamped(
            in: mapRect.insetBy(dx: GameConfig.playerCollisionRadius, dy: GameConfig.playerCollisionRadius)
        )

        let movementStrength: CGFloat = movementInput == .zero ? 0 : 1
        figure.update(deltaTime: deltaTime, facingAngle: facingAngle, movementStrength: movementStrength)
        updateDirectionalHeight()
        shadowNode.xScale = 1 - movementStrength * 0.08
        shadowNode.yScale = 1 - movementStrength * 0.14
    }

    func takeDamage(_ damage: CGFloat) -> Bool {
        currentHP = max(0, currentHP - damage)

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

    /// Tests the actual rendered 3D character silhouette rather than the ground
    /// ring, a rectangle, or a single ellipse.
    func containsHitPoint(_ worldPoint: CGPoint) -> Bool {
        let localPoint = CGPoint(
            x: worldPoint.x - position.x,
            y: worldPoint.y - position.y
        )
        let directionIndex = Self.directionIndex(for: facingAngle)
        if hitMasks[directionIndex] == nil {
            hitMasks[directionIndex] = figure.makeHitMask(directionIndex: directionIndex)
        }
        guard let hitMask = hitMasks[directionIndex] else { return false }

        let pointInViewport = CGPoint(
            x: (localPoint.x - modelNode.position.x)
                / max(abs(modelNode.xScale) * GameConfig.playerHitMaskWidthScale, 0.001)
                + GameConfig.playerModelViewportSize.width * 0.5,
            y: (localPoint.y - modelNode.position.y)
                / max(abs(modelNode.yScale) * GameConfig.playerHitMaskHeightScale, 0.001)
                + GameConfig.playerModelViewportSize.height * 0.5
        )
        return hitMask.contains(
            viewportPoint: pointInViewport,
            viewportSize: GameConfig.playerModelViewportSize
        )
    }

    private func updateFacing(with input: CGVector) {
        facingAngle = atan2(input.dx, -input.dy)
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

    private static func directionIndex(for angle: CGFloat) -> Int {
        let fullTurn = CGFloat.pi * 2
        let normalized = angle.truncatingRemainder(dividingBy: fullTurn)
        let positive = normalized >= 0 ? normalized : normalized + fullTurn
        return Int((positive / fullTurn * 24).rounded()) % 24
    }

}

private struct PlayerAlphaHitMask {
    private let width: Int
    private let height: Int
    private let alpha: [UInt8]

    init(image: UIImage) {
        guard let cgImage = image.cgImage else {
            width = 1
            height = 1
            alpha = [0]
            return
        }

        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        var pixels = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
        pixels.withUnsafeMutableBytes { storage in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: imageWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            // Store row zero as the top row, matching the source PNG orientation.
            context.translateBy(x: 0, y: CGFloat(imageHeight))
            context.scaleBy(x: 1, y: -1)
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
            )
        }
        width = imageWidth
        height = imageHeight
        alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        if GameConfig.debugProjectileLoggingEnabled {
            let solidPixelCount = alpha.reduce(into: 0) { count, value in
                if value >= 64 { count += 1 }
            }
            let coverage = CGFloat(solidPixelCount) / CGFloat(max(1, alpha.count))
            NSLog("PLAYER HIT MASK solidCoverage=%.3f", coverage)
            assert(
                coverage > 0.001 && coverage < 0.50,
                "The player hit mask must contain only the rendered character silhouette."
            )
        }
    }

    func contains(viewportPoint: CGPoint, viewportSize: CGSize) -> Bool {
        guard width > 1, height > 1 else { return false }
        let u = viewportPoint.x / viewportSize.width
        let vFromBottom = viewportPoint.y / viewportSize.height
        guard (0...1).contains(u), (0...1).contains(vFromBottom) else { return false }

        let pixelX = min(width - 1, max(0, Int(u * CGFloat(width))))
        let pixelY = min(height - 1, max(0, Int((1 - vFromBottom) * CGFloat(height))))
        // Ignore the faint anti-aliased fringe and follow the visibly solid body.
        return alpha[pixelY * width + pixelX] >= 64
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

        let armSwing = sin(walkPhase) * 0.62 * clampedStrength
        let legSwing = sin(walkPhase) * 0.72 * clampedStrength
        let bodyBob = abs(sin(walkPhase)) * 0.10 * clampedStrength
        let bodyRoll = sin(walkPhase) * 0.06 * clampedStrength

        bodyNode.position.y = 1.20 + Float(bodyBob)
        bodyNode.eulerAngles.z = Float(bodyRoll)

        leftArmPivot.eulerAngles.x = Float(armSwing)
        rightArmPivot.eulerAngles.x = Float(-armSwing)
        leftLegPivot.eulerAngles.x = Float(-legSwing)
        rightLegPivot.eulerAngles.x = Float(legSwing)
    }

    func makeHitMask(directionIndex: Int) -> PlayerAlphaHitMask? {
        guard let renderer = hitMaskRenderer else { return nil }
        let previousYaw = rootNode.eulerAngles.y
        rootNode.eulerAngles.y = Float(CGFloat(directionIndex) / 24 * .pi * 2)
        SCNTransaction.flush()
        let image = renderer.snapshot(
            atTime: 0,
            with: GameConfig.playerModelViewportSize,
            antialiasingMode: .multisampling4X
        )
        rootNode.eulerAngles.y = previousYaw
        return PlayerAlphaHitMask(image: image)
    }

    private func configureCamera() {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        camera.fieldOfView = 44
        camera.zNear = 0.01
        camera.zFar = 20
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 3.42, 2.58)
        cameraNode.eulerAngles = SCNVector3(-0.72, 0, 0)
        scene.rootNode.addChildNode(cameraNode)
    }

    private func configureLights() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        ambient.light?.color = UIColor(white: 0.94, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 900
        key.position = SCNVector3(1.6, 5.2, 2.2)
        scene.rootNode.addChildNode(key)
    }

    private func configureFigure() {
        scene.rootNode.addChildNode(rootNode)
        rootNode.position = SCNVector3(0, -0.36, 0)

        // Original dusk-fox. Head, torso, limbs and tail are independent
        // volumes, giving the character real gaps, shadows and depth.
        let coat = UIColor(red: 0.075, green: 0.085, blue: 0.105, alpha: 1)
        let outerFur = UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1)
        let paleFur = UIColor(red: 0.48, green: 0.45, blue: 0.38, alpha: 1)

        bodyNode.geometry = SCNCapsule(capRadius: 0.33, height: 1.10)
        bodyNode.geometry?.firstMaterial = material(color: coat)
        // Give the player a fuller torso from every angle. Depth is increased
        // more strongly so the side-on silhouette remains satisfyingly broad.
        bodyNode.scale = SCNVector3(1.08, 0.94, 1.18)
        bodyNode.position = SCNVector3(0, 1.14, 0)
        rootNode.addChildNode(bodyNode)

        let neck = SCNNode(geometry: SCNCapsule(capRadius: 0.20, height: 0.42))
        neck.geometry?.firstMaterial = material(color: outerFur)
        neck.position = SCNVector3(0, 0.48, 0)
        bodyNode.addChildNode(neck)

        headNode.geometry = SCNSphere(radius: 0.41)
        headNode.geometry?.firstMaterial = material(color: outerFur)
        headNode.scale = SCNVector3(1.0, 0.94, 0.96)
        headNode.position = SCNVector3(0, 0.78, 0.015)
        bodyNode.addChildNode(headNode)

        let muzzle = SCNNode(geometry: SCNCapsule(capRadius: 0.105, height: 0.36))
        muzzle.geometry?.firstMaterial = material(color: paleFur)
        muzzle.eulerAngles.x = .pi / 2
        muzzle.position = SCNVector3(0, -0.16, 0.38)
        headNode.addChildNode(muzzle)

        let nose = SCNNode(geometry: SCNSphere(radius: 0.052))
        nose.geometry?.firstMaterial = material(color: UIColor(red: 0.055, green: 0.035, blue: 0.035, alpha: 1))
        nose.position = SCNVector3(0, -0.16, 0.585)
        headNode.addChildNode(nose)

        for side: Float in [-1, 1] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.034))
            eye.geometry?.firstMaterial = material(
                color: UIColor(red: 0.96, green: 0.50, blue: 0.10, alpha: 1),
                emission: UIColor(red: 0.28, green: 0.07, blue: 0.01, alpha: 0.18)
            )
            eye.position = SCNVector3(0.145 * side, 0.015, 0.39)
            headNode.addChildNode(eye)

            let cheek = SCNNode(geometry: SCNSphere(radius: 0.17))
            cheek.geometry?.firstMaterial = material(color: paleFur)
            cheek.scale = SCNVector3(0.82, 1.0, 0.32)
            cheek.position = SCNVector3(0.22 * side, -0.13, 0.34)
            headNode.addChildNode(cheek)

            let ear = SCNNode(geometry: SCNCone(topRadius: 0.012, bottomRadius: 0.13, height: 0.38))
            ear.geometry?.firstMaterial = material(color: outerFur)
            ear.position = SCNVector3(0.24 * side, 0.38, -0.015)
            ear.eulerAngles.z = side < 0 ? -0.20 : 0.20
            headNode.addChildNode(ear)

            let armPivot = side < 0 ? leftArmPivot : rightArmPivot
            armPivot.position = SCNVector3(0.32 * side, 0.26, 0.015)
            bodyNode.addChildNode(armPivot)

            let arm = SCNNode(geometry: SCNCapsule(capRadius: 0.09, height: 0.52))
            arm.geometry?.firstMaterial = material(color: outerFur)
            arm.position = SCNVector3(0.035 * side, -0.21, 0.075)
            arm.eulerAngles.z = side < 0 ? 0.12 : -0.12
            armPivot.addChildNode(arm)

            let paw = SCNNode(geometry: SCNSphere(radius: 0.115))
            paw.geometry?.firstMaterial = material(color: outerFur)
            paw.scale = SCNVector3(0.90, 1.08, 0.90)
            paw.position = SCNVector3(0.065 * side, -0.46, 0.13)
            armPivot.addChildNode(paw)

            let legPivot = side < 0 ? leftLegPivot : rightLegPivot
            legPivot.position = SCNVector3(0.18 * side, -0.42, -0.015)
            bodyNode.addChildNode(legPivot)

            let leg = SCNNode(geometry: SCNCapsule(capRadius: 0.105, height: 0.48))
            leg.geometry?.firstMaterial = material(color: outerFur)
            leg.position = SCNVector3(0, -0.23, 0.015)
            legPivot.addChildNode(leg)

            let foot = side < 0 ? leftFootNode : rightFootNode
            foot.geometry = SCNSphere(radius: 0.145)
            foot.geometry?.firstMaterial = material(color: outerFur)
            foot.scale = SCNVector3(1.12, 0.62, 1.32)
            foot.position = SCNVector3(0.025 * side, -0.50, 0.10)
            legPivot.addChildNode(foot)
        }

        let chestFur = SCNNode(geometry: SCNSphere(radius: 0.28))
        chestFur.geometry?.firstMaterial = material(color: paleFur)
        chestFur.scale = SCNVector3(0.78, 1.18, 0.17)
        chestFur.position = SCNVector3(0, 0.04, 0.31)
        bodyNode.addChildNode(chestFur)

        let scarf = SCNNode(geometry: SCNTorus(ringRadius: 0.225, pipeRadius: 0.045))
        scarf.geometry?.firstMaterial = material(color: UIColor(red: 0.47, green: 0.045, blue: 0.065, alpha: 1))
        scarf.eulerAngles.x = .pi / 2
        scarf.position = SCNVector3(0, 0.45, 0)
        bodyNode.addChildNode(scarf)

        let tail = SCNNode(geometry: SCNCapsule(capRadius: 0.105, height: 0.62))
        tail.geometry?.firstMaterial = material(color: outerFur)
        tail.position = SCNVector3(-0.31, -0.27, -0.22)
        tail.eulerAngles.z = 0.72
        tail.eulerAngles.x = -0.16
        bodyNode.addChildNode(tail)

        let tailTip = SCNNode(geometry: SCNSphere(radius: 0.115))
        tailTip.geometry?.firstMaterial = material(color: paleFur)
        tailTip.position = SCNVector3(0, 0.28, 0)
        tail.addChildNode(tailTip)
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
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.78
        material.metalness.contents = 0.0
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
