import SpriteKit
import UIKit

final class GameScene: SKScene {
    private struct PendingHyperchargeExplosion {
        var timeRemaining: TimeInterval
        let explosion: ExplosionSpec
        let coreNode: SKNode
    }

    private enum AutoWallPhase: CaseIterable {
        case bottomCenter
        case bottomLeft
        case leftMid
        case topLeft
        case topCenter
        case topRight
        case rightMid
        case bottomRight
        case center
        case complete

        var fileLabel: String {
            switch self {
            case .bottomCenter:
                return "bottom-center"
            case .bottomLeft:
                return "bottom-left"
            case .leftMid:
                return "left-mid"
            case .topLeft:
                return "top-left"
            case .topCenter:
                return "top-center"
            case .topRight:
                return "top-right"
            case .rightMid:
                return "right-mid"
            case .bottomRight:
                return "bottom-right"
            case .center:
                return "center"
            case .complete:
                return "complete"
            }
        }
    }

    private let hideDebugHUD = ProcessInfo.processInfo.environment["BULLETDODGE_HIDE_HUD"] == "1"
    private let autoWallTest = ProcessInfo.processInfo.environment["BULLETDODGE_AUTO_WALL_TEST"] == "1"
    private let autoAttackTest = ProcessInfo.processInfo.environment["BULLETDODGE_AUTO_ATTACK_TEST"] == "1"
    private let autoWallCapture = ProcessInfo.processInfo.environment["BULLETDODGE_AUTO_WALL_CAPTURE"] == "1"
    private let autoAttackCapture = ProcessInfo.processInfo.environment["BULLETDODGE_AUTO_ATTACK_CAPTURE"] == "1"
    private let sessionStore: GameSessionStore
    private let onGameOver: (GameResult) -> Void

    private let mapNode = SKShapeNode(rectOf: GameConfig.mapSize, cornerRadius: 0)
    private let player = PlayerNode()
    private let enemy = EnemyNode()
    private let joystick: VirtualJoystick
    private let playerSpeedSetting: PlayerSpeedSetting
    private let playerMovementSpeed: CGFloat
    private let gameCamera = SKCameraNode()
    private let ammoIndicator = SKNode()
    private let hyperchargeAura = SKNode()
    private let ammoBackdrop = SKShapeNode(
        rectOf: CGSize(width: 48, height: 18),
        cornerRadius: 9
    )
    private var ammoPips: [SKShapeNode] = []
    private let backgroundContainer = SKNode()
    private let explosionContainer = SKNode()
    private let hitFeedback = UIImpactFeedbackGenerator(style: .light)

    private var bullets: [BulletNode] = []
    private var lastUpdateTime: TimeInterval = 0
    private var survivalTime: TimeInterval = 0
    private var dodgedCount = 0
    private var hitCount = 0
    private var gameEnded = false
    private var screenShakeTimeRemaining: TimeInterval = 0
    private var joystickTouch: UITouch?
    private var enemyReferencePoint: CGPoint = .zero
    private var queuedEnemyTargetPoint: CGPoint?
    private var queuedEnemyAttackVariant: ThornAttackVariant?
    private var pendingHyperchargeExplosions: [PendingHyperchargeExplosion] = []
    private var isHyperchargeActive = false
    private var isWallPressureRecoveryActive = false
    private var autoWallPhase: AutoWallPhase = .bottomCenter
    private var autoWallHoldTimeRemaining: TimeInterval = 0
    private var autoWallLogTimer: TimeInterval = 0
    private let autoWallLogFileName = "auto-wall.log"
    private var capturedAutoWallPhases = Set<AutoWallPhase>()
    private let autoAttackLogFileName = "auto-attack.log"
    private let autoAttackCaptureMoments: [TimeInterval] = [0.00, 0.05, 0.10, 0.13, 0.18, 0.24, 0.30, 0.34, 0.38, 0.42, 0.46, 0.50, 0.56, 0.62]
    private var autoAttackCaptureSchedule: [(index: Int, triggerTime: TimeInterval)] = []
    private var currentAttackCaptureID = 0

    private let mapRect = CGRect(
        origin: CGPoint(
            x: -GameConfig.mapSize.width / 2,
            y: -GameConfig.stageVisualSize.height / 2 + GameConfig.stageBottomInset
        ),
        size: GameConfig.mapSize
    )
    private let stageRect = CGRect(
        origin: CGPoint(x: -GameConfig.stageVisualSize.width / 2, y: -GameConfig.stageVisualSize.height / 2),
        size: GameConfig.stageVisualSize
    )
    private var playableRect: CGRect {
        CGRect(
            x: mapRect.minX + GameConfig.playableLeftInset,
            y: mapRect.minY - GameConfig.playableBottomExtension,
            width: mapRect.width - GameConfig.playableLeftInset - GameConfig.playableRightInset,
            height: mapRect.height + GameConfig.playableBottomExtension - GameConfig.playableTopInset
        )
    }

    var isGamePaused = false {
        didSet {
            isPaused = isGamePaused
        }
    }

    init(
        seed: UUID,
        joystickMode: JoystickMode,
        playerSpeedSetting: PlayerSpeedSetting,
        sessionStore: GameSessionStore,
        onGameOver: @escaping (GameResult) -> Void
    ) {
        joystick = VirtualJoystick(mode: joystickMode)
        self.playerSpeedSetting = playerSpeedSetting
        playerMovementSpeed = switch playerSpeedSetting {
        case .slow:
            GameConfig.slowPlayerSpeed
        case .normal:
            GameConfig.playerSpeed
        case .fast:
            GameConfig.fastPlayerSpeed
        case .ultraFast:
            GameConfig.ultraFastPlayerSpeed
        }
        self.sessionStore = sessionStore
        self.onGameOver = onGameOver
        super.init(size: CGSize(width: 932, height: 430))
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.05, green: 0.38, blue: 0.66, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        setupSceneIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutOverlayNodes()
        updateCameraScale()
        constrainEnemyToUpperLane()
        updateCameraPosition()
    }

    func setPaused(_ paused: Bool) {
        isGamePaused = paused
    }

    override func update(_ currentTime: TimeInterval) {
        guard !gameEnded else { return }

        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            publishSnapshot()
            return
        }

        let deltaTime = min(max(currentTime - lastUpdateTime, 0), 1.0 / 60.0)
        lastUpdateTime = currentTime

        survivalTime += deltaTime
        updateHyperchargeState()
        player.applyMovement(
            input: currentMovementInput,
            deltaTime: deltaTime,
            mapRect: playableRect,
            movementSpeed: playerMovementSpeed
        )
        player.position = constrainedArenaPosition(player.position, collisionRadius: GameConfig.playerCollisionRadius)
        if autoWallTest {
            updateAutoWallRoute(deltaTime: deltaTime)
        }
        updateWallPressureRecoveryState()
        if GameConfig.enemyMovementEnabled && !autoWallTest && !autoAttackTest {
            updateEnemyReferencePoint(deltaTime: deltaTime)
            let enemyAnchor = preferredEnemyAnchorPosition()
            enemy.updateMovement(
                deltaTime: deltaTime,
                desiredAnchor: enemyAnchor,
                playerPosition: player.position,
                mapRect: playableRect,
                visibleRect: currentVisibleRect
            )
            enemy.position = constrainedArenaPosition(
                enemy.position,
                collisionRadius: GameConfig.enemyCollisionRadius
            )
        } else {
            enemy.updateStationaryPose(deltaTime: deltaTime)
        }
        enemy.updateReload(deltaTime: deltaTime)

        if GameConfig.enemyAttacksEnabled && !autoWallTest {
            switch enemy.updateAttack(deltaTime: deltaTime) {
            case .none:
                break
            case .beganThrow(let shotContext):
                let targetPoint = makeThrowTargetPoint(for: shotContext)
                queuedEnemyTargetPoint = targetPoint
                queuedEnemyAttackVariant = currentAttackVariant
                enemy.faceAttack(toward: targetPoint)
                scheduleAutoAttackCaptures()
            case .releaseProjectile(let shotContext):
                let targetPoint = queuedEnemyTargetPoint
                    ?? makeThrowTargetPoint(for: shotContext)
                let attackVariant = queuedEnemyAttackVariant
                    ?? currentAttackVariant
                queuedEnemyTargetPoint = nil
                queuedEnemyAttackVariant = nil
                spawnBullet(toward: targetPoint, variant: attackVariant)
            }
        }

        updateBullets(deltaTime: deltaTime)
        updatePendingHyperchargeExplosions(deltaTime: deltaTime)
        updateCameraShake(deltaTime: deltaTime)
        updateCameraPosition()
        updateAmmoLabel()
        publishSnapshot()
        logAutoWallState(deltaTime: deltaTime)
        runAutoAttackCaptureIfNeeded()
    }

    private var currentAttackVariant: ThornAttackVariant {
        isHyperchargeActive ? .hypercharge : .normal
    }

    private func updateHyperchargeState() {
        let shouldBeActive = GameConfig.hyperchargeStartTimes.contains { startTime in
            survivalTime >= startTime
                && survivalTime < startTime + GameConfig.hyperchargeDuration
        }
        guard shouldBeActive != isHyperchargeActive else { return }

        isHyperchargeActive = shouldBeActive
        setHyperchargeAuraActive(shouldBeActive)

        if shouldBeActive {
            // Projectiles and throw wind-ups keep the variant they had when
            // launched. Only attacks begun after activation become purple.
            spawnHyperchargeActivationBurst()
        }
    }

    private func configureHyperchargeAura() {
        guard hyperchargeAura.parent == nil else { return }
        hyperchargeAura.zPosition = -2
        hyperchargeAura.isHidden = true

        let groundRing = SKShapeNode(
            ellipseOf: CGSize(
                width: GameConfig.enemyVisualRadius * 2.15,
                height: GameConfig.enemyVisualRadius * 0.90
            )
        )
        groundRing.fillColor = UIColor(red: 0.39, green: 0.05, blue: 0.70, alpha: 0.22)
        groundRing.strokeColor = UIColor(red: 0.76, green: 0.27, blue: 1.0, alpha: 0.96)
        groundRing.lineWidth = 3.2
        groundRing.glowWidth = 9
        groundRing.run(.repeatForever(.sequence([
            .group([
                .scale(to: 1.08, duration: 0.34),
                .fadeAlpha(to: 0.72, duration: 0.34)
            ]),
            .group([
                .scale(to: 0.94, duration: 0.34),
                .fadeAlpha(to: 1.0, duration: 0.34)
            ])
        ])))
        hyperchargeAura.addChild(groundRing)

        let orbit = SKNode()
        orbit.position = CGPoint(x: 0, y: GameConfig.enemyVisualRadius * 0.32)
        for index in 0..<6 {
            let angle = CGFloat(index) * (.pi * 2 / 6)
            let spark = SKShapeNode(circleOfRadius: 3.2)
            spark.position = CGPoint(
                x: cos(angle) * GameConfig.enemyVisualRadius * 0.88,
                y: sin(angle) * GameConfig.enemyVisualRadius * 0.58
            )
            spark.fillColor = UIColor(red: 0.80, green: 0.38, blue: 1.0, alpha: 0.92)
            spark.strokeColor = UIColor.white.withAlphaComponent(0.75)
            spark.lineWidth = 0.7
            spark.glowWidth = 6
            orbit.addChild(spark)
        }
        orbit.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 1.15)))
        hyperchargeAura.addChild(orbit)
        enemy.addChild(hyperchargeAura)
    }

    private func setHyperchargeAuraActive(_ isActive: Bool) {
        hyperchargeAura.isHidden = !isActive
    }

    private func spawnHyperchargeActivationBurst() {
        let ring = SKShapeNode(circleOfRadius: GameConfig.enemyVisualRadius * 0.74)
        ring.position = enemy.position
        ring.zPosition = 29
        ring.fillColor = UIColor.clear
        ring.strokeColor = UIColor(red: 0.73, green: 0.22, blue: 1.0, alpha: 0.95)
        ring.lineWidth = 5
        ring.glowWidth = 14
        addChild(ring)
        ring.run(.sequence([
            .group([
                .scale(to: 2.45, duration: 0.32),
                .fadeOut(withDuration: 0.32)
            ]),
            .removeFromParent()
        ]))
    }

    private func constrainedArenaPosition(_ point: CGPoint, collisionRadius: CGFloat) -> CGPoint {
        let baseRect = playableRect.insetBy(dx: collisionRadius, dy: collisionRadius)
        let clampedY = min(max(point.y, baseRect.minY), baseRect.maxY)
        let verticalProgress = (clampedY - baseRect.minY) / max(1, baseRect.height)
        let leftInset = GameConfig.playableUpperLeftWallInset * verticalProgress
        let rightInset = GameConfig.playableUpperRightWallInset * verticalProgress
        let horizontalRect = CGRect(
            x: baseRect.minX + leftInset,
            y: baseRect.minY,
            width: max(0, baseRect.width - leftInset - rightInset),
            height: baseRect.height
        )

        return CGPoint(
            x: min(max(point.x, horizontalRect.minX), horizontalRect.maxX),
            y: clampedY
        )
    }

    private func updateAutoWallRoute(deltaTime: TimeInterval) {
        if autoWallHoldTimeRemaining > 0 {
            autoWallHoldTimeRemaining = max(0, autoWallHoldTimeRemaining - deltaTime)
            return
        }

        let target = autoWallTargetPoint(for: autoWallPhase)
        let distance = hypot(player.position.x - target.x, player.position.y - target.y)
        guard distance <= 6 else { return }

        captureAutoWallCheckpointIfNeeded()

        switch autoWallPhase {
        case .bottomCenter:
            autoWallPhase = .bottomLeft
        case .bottomLeft:
            autoWallPhase = .leftMid
        case .leftMid:
            autoWallPhase = .topLeft
        case .topLeft:
            autoWallPhase = .topCenter
        case .topCenter:
            autoWallPhase = .topRight
        case .topRight:
            autoWallPhase = .rightMid
        case .rightMid:
            autoWallPhase = .bottomRight
        case .bottomRight:
            autoWallPhase = .center
        case .center:
            autoWallPhase = .complete
            captureAutoWallCheckpointIfNeeded()
        case .complete:
            break
        }
        autoWallHoldTimeRemaining = autoWallPhase == .complete ? 0 : 0.7
    }

    private func logAutoWallState(deltaTime: TimeInterval) {
        guard autoWallTest else { return }
        autoWallLogTimer += deltaTime
        guard autoWallLogTimer >= 1 else { return }
        autoWallLogTimer = 0
        appendAutoWallLog(
            "AUTO_WALL phase=\(String(describing: autoWallPhase)) " +
            "pos=(\(Int(player.position.x)),\(Int(player.position.y))) " +
            "input=(\(String(format: "%.2f", currentMovementInput.dx)),\(String(format: "%.2f", currentMovementInput.dy)))"
        )
    }

    private func clearAutoWallLogIfNeeded() {
        guard autoWallTest else { return }
        try? "".write(to: autoWallLogURL, atomically: true, encoding: .utf8)
    }

    private func appendAutoWallLog(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: autoWallLogURL.path),
           let handle = try? FileHandle(forWritingTo: autoWallLogURL) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
            }
            return
        }

        try? data.write(to: autoWallLogURL)
    }

    private func captureAutoWallCheckpointIfNeeded() {
        guard autoWallCapture, autoWallPhase != .complete, !capturedAutoWallPhases.contains(autoWallPhase) else { return }
        let phase = autoWallPhase
        capturedAutoWallPhases.insert(phase)
        let captureIndex = capturedAutoWallPhases.count

        Task { @MainActor [weak self] in
            guard let self, let view = self.view else { return }
            let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
            let image = renderer.image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            guard let data = image.pngData() else { return }
            let fileURL = self.autoWallCaptureDirectoryURL
                .appendingPathComponent(String(format: "%02d_%@.png", captureIndex, phase.fileLabel))
            try? data.write(to: fileURL)
            self.appendAutoWallLog("CAPTURE saved=\(fileURL.lastPathComponent)")
        }
    }

    private var autoWallLogURL: URL {
        let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent(autoWallLogFileName)
    }

    private var autoWallCaptureDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("auto-wall-captures", isDirectory: true)
    }

    private var autoAttackLogURL: URL {
        let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent(autoAttackLogFileName)
    }

    private var autoAttackCaptureDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("auto-attack-captures", isDirectory: true)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where joystickTouch == nil {
            let point = touch.location(in: gameCamera)
            if joystick.activationFrame(in: size).contains(point) {
                joystickTouch = touch
                joystick.beginTracking(touch: touch, at: point)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where joystick.containsTrackingTouch(touch) {
            joystick.updateTracking(touch: touch, at: touch.location(in: gameCamera))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouchesIfNeeded(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouchesIfNeeded(touches)
    }

    private var currentMovementInput: CGVector {
        guard autoWallTest else { return autoAttackTest ? .zero : joystick.inputVector }

        if autoWallHoldTimeRemaining > 0 {
            return .zero
        }

        let target = autoWallTargetPoint(for: autoWallPhase)
        return CGVector(
            dx: target.x - player.position.x,
            dy: target.y - player.position.y
        ).normalized
    }

    private func setupSceneIfNeeded() {
        guard children.isEmpty else { return }
        sessionStore.reset()

        mapNode.zPosition = -100
        backgroundContainer.zPosition = -10
        player.zPosition = 30
        enemy.zPosition = 30
        explosionContainer.zPosition = 20
        gameCamera.zPosition = 100
        joystick.zPosition = 200

        addChild(mapNode)
        addChild(player)
        addChild(enemy)
        addChild(explosionContainer)
        addChild(gameCamera)
        addChild(ammoIndicator)
        camera = gameCamera
        gameCamera.addChild(joystick)

        mapNode.fillColor = .clear
        mapNode.strokeColor = .clear
        mapNode.lineWidth = 0
        mapNode.addChild(backgroundContainer)
        buildMapBackground()

        configureAmmoIndicator()
        configureHyperchargeAura()
        joystick.isHidden = autoWallCapture

        resetState()
        BulletNode.prewarmVisualResources()
        hitFeedback.prepare()
        layoutOverlayNodes()
#if DEBUG
        if ProcessInfo.processInfo.environment["BULLETDODGE_PREVIEW_FLOATING_JOYSTICK"] == "1" {
            let origin = CGPoint(
                x: -size.width / 2 + 106,
                y: -size.height / 2 + 96
            )
            joystick.showFloatingPreview(
                at: origin,
                draggedTo: CGPoint(x: origin.x + 84, y: origin.y + 28)
            )
        }
#endif
        updateCameraScale()
        updateCameraPosition()
        updateAmmoLabel()
    }

    private func resetState() {
        bullets.forEach { $0.removeFromParent() }
        bullets.removeAll()
        explosionContainer.removeAllChildren()
        lastUpdateTime = 0
        survivalTime = 0
#if DEBUG
        survivalTime = TimeInterval(
            ProcessInfo.processInfo.environment["BULLETDODGE_START_TIME"] ?? "0"
        ) ?? 0
#endif
        dodgedCount = 0
        hitCount = 0
        gameEnded = false
        screenShakeTimeRemaining = 0
        joystickTouch = nil
        autoWallPhase = .bottomCenter
        autoWallHoldTimeRemaining = 0
        autoWallLogTimer = 0
        capturedAutoWallPhases.removeAll()
        autoAttackCaptureSchedule.removeAll()
        currentAttackCaptureID = 0
        queuedEnemyTargetPoint = nil
        queuedEnemyAttackVariant = nil
        pendingHyperchargeExplosions.forEach { $0.coreNode.removeFromParent() }
        pendingHyperchargeExplosions.removeAll()
        isHyperchargeActive = false
        setHyperchargeAuraActive(false)
        isWallPressureRecoveryActive = false
        joystick.reset()

        player.reset()
        enemy.reset()
        enemy.setWallRecoveryActive(false)
        player.alpha = GameConfig.debugHideActorsEnabled ? 0 : 1
        enemy.alpha = GameConfig.debugHideActorsEnabled ? 0 : 1

        if autoWallTest {
            player.position = CGPoint(
                x: playableRect.midX,
                y: playableRect.minY + GameConfig.playerCollisionRadius
            )
        } else if autoAttackTest {
            player.position = CGPoint(
                x: playableRect.midX,
                y: playableRect.midY - GameConfig.tileSize * 2.6
            )
        } else if GameConfig.debugCornerAttackTestEnabled {
            let margin = GameConfig.playerCollisionRadius
            switch GameConfig.debugCornerStartPosition {
            case "top-left":
                player.position = CGPoint(x: playableRect.minX + margin, y: playableRect.maxY - margin)
            case "top-right":
                player.position = CGPoint(x: playableRect.maxX - margin, y: playableRect.maxY - margin)
            case "bottom-right":
                player.position = CGPoint(x: playableRect.maxX - margin, y: playableRect.minY + margin)
            default:
                player.position = CGPoint(x: playableRect.minX + margin, y: playableRect.minY + margin)
            }
        } else {
            player.position = .zero
        }
        enemyReferencePoint = player.position
        if autoAttackTest {
            enemy.position = CGPoint(
                x: playableRect.midX,
                y: playableRect.midY + GameConfig.tileSize * 2.8
            )
        } else {
            enemy.position = preferredEnemyAnchorPosition()
        }
        clearAutoWallLogIfNeeded()
        clearAutoWallCaptureDirectoryIfNeeded()
        clearAutoAttackLogIfNeeded()
        clearAutoAttackCaptureDirectoryIfNeeded()
    }

    private func autoWallTargetPoint(for phase: AutoWallPhase) -> CGPoint {
        let margin = GameConfig.playerCollisionRadius
        let left = playableRect.minX + margin
        let right = playableRect.maxX - margin
        let bottom = playableRect.minY + margin
        let top = playableRect.maxY - margin
        let midX = playableRect.midX
        let midY = playableRect.midY

        switch phase {
        case .bottomCenter:
            return CGPoint(x: midX, y: bottom)
        case .bottomLeft:
            return CGPoint(x: left, y: bottom)
        case .leftMid:
            return CGPoint(x: left, y: midY)
        case .topLeft:
            return CGPoint(x: left, y: top)
        case .topCenter:
            return CGPoint(x: midX, y: top)
        case .topRight:
            return CGPoint(x: right, y: top)
        case .rightMid:
            return CGPoint(x: right, y: midY)
        case .bottomRight:
            return CGPoint(x: right, y: bottom)
        case .center:
            return CGPoint(x: midX, y: midY)
        case .complete:
            return CGPoint(x: midX, y: midY)
        }
    }

    private func clearAutoWallCaptureDirectoryIfNeeded() {
        guard autoWallCapture else { return }
        try? FileManager.default.removeItem(at: autoWallCaptureDirectoryURL)
        try? FileManager.default.createDirectory(at: autoWallCaptureDirectoryURL, withIntermediateDirectories: true)
    }

    private func clearAutoAttackLogIfNeeded() {
        guard autoAttackCapture else { return }
        try? "".write(to: autoAttackLogURL, atomically: true, encoding: .utf8)
    }

    private func clearAutoAttackCaptureDirectoryIfNeeded() {
        guard autoAttackCapture else { return }
        try? FileManager.default.removeItem(at: autoAttackCaptureDirectoryURL)
        try? FileManager.default.createDirectory(at: autoAttackCaptureDirectoryURL, withIntermediateDirectories: true)
    }

    private func layoutOverlayNodes() {
        joystick.position = CGPoint(
            x: -size.width / 2 + GameConfig.joystickLeftInset,
            y: -size.height / 2 + GameConfig.joystickBottomInset
        )

    }

    private func buildMapBackground() {
        backgroundContainer.removeAllChildren()

        if let mapImage = UIImage(named: "arena_map_v8") {
            let texture = SKTexture(image: mapImage)
            texture.filteringMode = .linear

            let topExtensionHeight = GameConfig.tileSize * 16.0
            let bottomExtensionHeight = GameConfig.tileSize * 8.0
            let totalHeight = GameConfig.stageVisualSize.height
                + topExtensionHeight
                + bottomExtensionHeight
            let map = SKSpriteNode(
                texture: texture,
                size: CGSize(
                    width: GameConfig.stageVisualSize.width,
                    height: totalHeight
                )
            )
            map.position = CGPoint(
                x: 0,
                y: (topExtensionHeight - bottomExtensionHeight) / 2
            )
            map.zPosition = -20

            let sourceBottomEdge = Float(
                GameConfig.stageBottomInset / GameConfig.stageVisualSize.height
            )
            let sourceTopEdge = Float(
                (GameConfig.stageBottomInset + playableRect.height)
                    / GameConfig.stageVisualSize.height
            )
            let destinationBottomEdge = Float(
                (bottomExtensionHeight + GameConfig.stageBottomInset) / totalHeight
            )
            let destinationTopEdge = Float(
                (bottomExtensionHeight + GameConfig.stageBottomInset + playableRect.height)
                    / totalHeight
            )

            map.warpGeometry = SKWarpGeometryGrid(
                columns: 1,
                rows: 3,
                sourcePositions: [
                    SIMD2<Float>(0, 0),
                    SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, sourceBottomEdge),
                    SIMD2<Float>(1, sourceBottomEdge),
                    SIMD2<Float>(0, sourceTopEdge),
                    SIMD2<Float>(1, sourceTopEdge),
                    SIMD2<Float>(0, 1),
                    SIMD2<Float>(1, 1)
                ],
                destinationPositions: [
                    SIMD2<Float>(0, 0),
                    SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, destinationBottomEdge),
                    SIMD2<Float>(1, destinationBottomEdge),
                    SIMD2<Float>(0, destinationTopEdge),
                    SIMD2<Float>(1, destinationTopEdge),
                    SIMD2<Float>(0, 1),
                    SIMD2<Float>(1, 1)
                ]
            )
            backgroundContainer.addChild(map)
        }
    }

    /// Clips the dedicated arena material to the exact movement polygon.
    /// The artwork follows gameplay geometry; no movement constant is inferred
    /// from the generated background.
    private func makePlayableFloorLayer() -> SKNode {
        let crop = SKCropNode()
        crop.zPosition = -10

        let bottomLeft = CGPoint(x: playableRect.minX, y: playableRect.minY)
        let bottomRight = CGPoint(x: playableRect.maxX, y: playableRect.minY)
        let topLeft = CGPoint(
            x: playableRect.minX + GameConfig.playableUpperLeftWallInset,
            y: playableRect.maxY
        )
        let topRight = CGPoint(
            x: playableRect.maxX - GameConfig.playableUpperRightWallInset,
            y: playableRect.maxY
        )

        let maskPath = CGMutablePath()
        maskPath.move(to: bottomLeft)
        maskPath.addLine(to: bottomRight)
        maskPath.addLine(to: topRight)
        maskPath.addLine(to: topLeft)
        maskPath.closeSubpath()

        let mask = SKShapeNode(path: maskPath)
        mask.fillColor = .white
        mask.strokeColor = .white
        mask.lineWidth = 2
        crop.maskNode = mask

        if let floorImage = UIImage(named: "arena_playable_floor") {
            let texture = SKTexture(image: floorImage)
            texture.filteringMode = .linear
            let floor = SKSpriteNode(texture: texture, size: GameConfig.stageVisualSize)
            floor.position = .zero
            floor.warpGeometry = SKWarpGeometryGrid(
                columns: 1,
                rows: 1,
                sourcePositions: [
                    SIMD2<Float>(0, 0),
                    SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, 1),
                    SIMD2<Float>(1, 1)
                ],
                destinationPositions: [
                    SIMD2<Float>(0, 0),
                    SIMD2<Float>(1, 0),
                    SIMD2<Float>(0.04, 1),
                    SIMD2<Float>(0.96, 1)
                ]
            )
            crop.addChild(floor)
            crop.addChild(makeFloorNavigationPattern())
        } else {
            let fallback = SKShapeNode(path: maskPath)
            fallback.fillColor = UIColor(red: 0.54, green: 0.66, blue: 0.71, alpha: 1)
            fallback.strokeColor = .clear
            crop.addChild(fallback)
            crop.addChild(makeFloorNavigationPattern())
        }

        return crop
    }

    /// Repeated inlays provide stable distance cues while moving without
    /// participating in physics or changing the calibrated arena dimensions.
    private func makeFloorNavigationPattern() -> SKNode {
        let container = SKNode()
        container.zPosition = 2

        let spacing = GameConfig.tileSize * 3
        let lineColor = UIColor(red: 0.12, green: 0.34, blue: 0.40, alpha: 0.20)
        let accentColor = UIColor(red: 0.68, green: 0.38, blue: 0.20, alpha: 0.52)
        let bottomLeft = CGPoint(x: playableRect.minX, y: playableRect.minY)
        let bottomRight = CGPoint(x: playableRect.maxX, y: playableRect.minY)
        let topLeft = CGPoint(
            x: playableRect.minX + GameConfig.playableUpperLeftWallInset,
            y: playableRect.maxY
        )
        let topRight = CGPoint(
            x: playableRect.maxX - GameConfig.playableUpperRightWallInset,
            y: playableRect.maxY
        )
        let columnCount = max(2, Int(round(playableRect.width / spacing)))
        let rowCount = max(2, Int(round(playableRect.height / spacing)))

        let gridPath = CGMutablePath()
        for column in 1..<columnCount {
            let fraction = CGFloat(column) / CGFloat(columnCount)
            gridPath.move(to: CGPoint(
                x: bottomLeft.x + (bottomRight.x - bottomLeft.x) * fraction,
                y: bottomLeft.y
            ))
            gridPath.addLine(to: CGPoint(
                x: topLeft.x + (topRight.x - topLeft.x) * fraction,
                y: topLeft.y
            ))
        }

        for row in 1..<rowCount {
            let depth = CGFloat(row) / CGFloat(rowCount)
            let rowY = bottomLeft.y + (topLeft.y - bottomLeft.y) * depth
            let rowLeft = bottomLeft.x + (topLeft.x - bottomLeft.x) * depth
            let rowRight = bottomRight.x + (topRight.x - bottomRight.x) * depth
            gridPath.move(to: CGPoint(x: rowLeft, y: rowY))
            gridPath.addLine(to: CGPoint(x: rowRight, y: rowY))
        }

        let grid = SKShapeNode(path: gridPath)
        grid.strokeColor = lineColor
        grid.lineWidth = 1.15
        grid.zPosition = 0
        container.addChild(grid)

        for row in 1..<rowCount {
            let depth = CGFloat(row) / CGFloat(rowCount)
            let markerY = bottomLeft.y + (topLeft.y - bottomLeft.y) * depth
            let rowLeft = bottomLeft.x + (topLeft.x - bottomLeft.x) * depth
            let rowRight = bottomRight.x + (topRight.x - bottomRight.x) * depth

            for column in 1..<columnCount {
                let fraction = CGFloat(column) / CGFloat(columnCount)
                let markerX = rowLeft + (rowRight - rowLeft) * fraction
                let markerIsLarge = (row + column).isMultiple(of: 2)
                let marker = SKShapeNode(
                    rectOf: CGSize(
                        width: markerIsLarge ? 7 : 5,
                        height: markerIsLarge ? 4.8 : 3.4
                    ),
                    cornerRadius: 1
                )
                marker.position = CGPoint(x: markerX, y: markerY)
                marker.zRotation = .pi / 4
                marker.fillColor = (row + column).isMultiple(of: 3)
                    ? accentColor
                    : UIColor(red: 0.18, green: 0.67, blue: 0.70, alpha: 0.46)
                marker.strokeColor = UIColor.white.withAlphaComponent(0.16)
                marker.lineWidth = 0.7
                marker.zPosition = 1
                container.addChild(marker)
            }
        }

        return container
    }

    /// Adds a purely visual boundary on the exact arena polygon used by movement.
    /// No collision values are duplicated here: the path is derived from
    /// `playableRect` and the existing far-wall taper.
    private func makePlayableBoundaryLayer() -> SKNode {
        let container = SKNode()
        container.zPosition = -3.15

        let bottomLeft = CGPoint(x: playableRect.minX, y: playableRect.minY)
        let bottomRight = CGPoint(x: playableRect.maxX, y: playableRect.minY)
        let topLeft = CGPoint(
            x: playableRect.minX + GameConfig.playableUpperLeftWallInset,
            y: playableRect.maxY
        )
        let topRight = CGPoint(
            x: playableRect.maxX - GameConfig.playableUpperRightWallInset,
            y: playableRect.maxY
        )

        let boundaryPath = CGMutablePath()
        boundaryPath.move(to: bottomLeft)
        boundaryPath.addLine(to: topLeft)
        boundaryPath.move(to: bottomRight)
        boundaryPath.addLine(to: topRight)

        // A shallow foundation lip remains on the same ground plane as the
        // arena. Its downward shadow gives height without making the perimeter
        // look like a lower platform.
        let dropShadow = SKShapeNode(path: boundaryPath)
        dropShadow.position = CGPoint(x: 0, y: -1.5)
        dropShadow.strokeColor = UIColor(red: 0.15, green: 0.13, blue: 0.08, alpha: 0.42)
        dropShadow.lineWidth = 4.5
        dropShadow.lineJoin = .round
        dropShadow.fillColor = .clear
        dropShadow.zPosition = 1
        container.addChild(dropShadow)

        let curb = SKShapeNode(path: boundaryPath)
        curb.strokeColor = UIColor(red: 0.78, green: 0.76, blue: 0.61, alpha: 0.94)
        curb.lineWidth = 3.4
        curb.lineJoin = .round
        curb.fillColor = .clear
        curb.zPosition = 2
        container.addChild(curb)

        let mineralBand = SKShapeNode(path: boundaryPath)
        mineralBand.strokeColor = UIColor(red: 0.57, green: 0.40, blue: 0.16, alpha: 0.88)
        mineralBand.lineWidth = 1.25
        mineralBand.lineJoin = .round
        mineralBand.fillColor = .clear
        mineralBand.zPosition = 3
        container.addChild(mineralBand)
        return container
    }

    private func makeFilledPolygon(_ points: [CGPoint], color: UIColor) -> SKShapeNode {
        let path = CGMutablePath()
        guard let first = points.first else {
            return SKShapeNode()
        }

        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()

        let shape = SKShapeNode(path: path)
        shape.fillColor = color
        shape.strokeColor = .clear
        return shape
    }

    private func addBoundarySignalTiles(
        to container: SKNode,
        bottomLeft: CGPoint,
        bottomRight: CGPoint,
        topLeft: CGPoint,
        topRight: CGPoint
    ) {
        func addTile(at point: CGPoint, rotation: CGFloat, index: Int) {
            let tile = SKShapeNode(
                rectOf: CGSize(width: index.isMultiple(of: 2) ? 9 : 6.5, height: 3.4),
                cornerRadius: 1.4
            )
            tile.position = point
            tile.zRotation = rotation
            tile.fillColor = index.isMultiple(of: 3)
                ? UIColor(red: 1.0, green: 0.70, blue: 0.28, alpha: 0.98)
                : UIColor(red: 0.30, green: 0.96, blue: 0.92, alpha: 0.98)
            tile.strokeColor = UIColor.white.withAlphaComponent(0.28)
            tile.lineWidth = 0.8
            tile.glowWidth = 0.9
            tile.zPosition = 5
            let delay = SKAction.wait(forDuration: TimeInterval(index % 5) * 0.12)
            tile.run(.repeatForever(.sequence([
                delay,
                .fadeAlpha(to: 0.48, duration: 0.48),
                .fadeAlpha(to: 1.0, duration: 0.48)
            ])))
            container.addChild(tile)
        }

        let sideCount = 13
        for index in 1..<sideCount {
            let t = CGFloat(index) / CGFloat(sideCount)
            let left = CGPoint(
                x: bottomLeft.x + (topLeft.x - bottomLeft.x) * t,
                y: bottomLeft.y + (topLeft.y - bottomLeft.y) * t
            )
            let right = CGPoint(
                x: bottomRight.x + (topRight.x - bottomRight.x) * t,
                y: bottomRight.y + (topRight.y - bottomRight.y) * t
            )
            let leftAngle = atan2(topLeft.y - bottomLeft.y, topLeft.x - bottomLeft.x)
            let rightAngle = atan2(topRight.y - bottomRight.y, topRight.x - bottomRight.x)
            addTile(at: CGPoint(x: left.x - 7, y: left.y), rotation: leftAngle, index: index)
            addTile(at: CGPoint(x: right.x + 7, y: right.y), rotation: rightAngle, index: index + 1)
        }

        let horizontalCount = 10
        for index in 1..<horizontalCount {
            let t = CGFloat(index) / CGFloat(horizontalCount)
            addTile(
                at: CGPoint(
                    x: bottomLeft.x + (bottomRight.x - bottomLeft.x) * t,
                    y: bottomLeft.y - 7
                ),
                rotation: 0,
                index: index + 20
            )
            addTile(
                at: CGPoint(
                    x: topLeft.x + (topRight.x - topLeft.x) * t,
                    y: topLeft.y + 7
                ),
                rotation: 0,
                index: index + 31
            )
        }
    }

    /// Original perimeter machinery built from layered SpriteKit geometry.
    /// Rotors, pistons and cores move independently to give the non-playable
    /// edge depth and life while remaining completely outside gameplay.
    private func makeKineticPerimeterDecor() -> SKNode {
        let container = SKNode()
        container.zPosition = -2.75

        let sideYPositions = [
            playableRect.minY + playableRect.height * 0.17,
            playableRect.minY + playableRect.height * 0.50,
            playableRect.minY + playableRect.height * 0.83
        ]
        for (index, y) in sideYPositions.enumerated() {
            let leftTower = makeTideEngine(onLeft: true, index: index)
            leftTower.position = CGPoint(x: stageRect.minX + 50, y: y)
            container.addChild(leftTower)

            let rightTower = makeTideEngine(onLeft: false, index: index)
            rightTower.position = CGPoint(x: stageRect.maxX - 50, y: y)
            container.addChild(rightTower)
        }

        let pylonXPositions: [CGFloat] = [-0.31, -0.155, 0, 0.155, 0.31]
        for (index, ratio) in pylonXPositions.enumerated() {
            let lowerPylon = makeFluxPylon(index: index, pointsUp: true)
            lowerPylon.position = CGPoint(
                x: playableRect.midX + playableRect.width * ratio,
                y: playableRect.minY - 64
            )
            container.addChild(lowerPylon)

            if index.isMultiple(of: 2) {
                let upperPylon = makeFluxPylon(index: index + 7, pointsUp: false)
                upperPylon.position = CGPoint(
                    x: playableRect.midX + playableRect.width * ratio,
                    y: playableRect.maxY + 45
                )
                container.addChild(upperPylon)
            }
        }

        return container
    }

    private func makeTideEngine(onLeft: Bool, index: Int) -> SKNode {
        let node = SKNode()
        let facing: CGFloat = onLeft ? 1 : -1

        let groundShadow = SKShapeNode(ellipseOf: CGSize(width: 82, height: 36))
        groundShadow.position = CGPoint(x: -facing * 5, y: -8)
        groundShadow.fillColor = UIColor.black.withAlphaComponent(0.32)
        groundShadow.strokeColor = .clear
        node.addChild(groundShadow)

        let rearHousing = SKShapeNode(circleOfRadius: 40)
        rearHousing.position = CGPoint(x: -facing * 4, y: 3)
        rearHousing.fillColor = UIColor(red: 0.035, green: 0.09, blue: 0.14, alpha: 1)
        rearHousing.strokeColor = UIColor(red: 0.33, green: 0.18, blue: 0.11, alpha: 1)
        rearHousing.lineWidth = 7
        node.addChild(rearHousing)

        let copperRing = SKShapeNode(circleOfRadius: 33)
        copperRing.position = rearHousing.position
        copperRing.fillColor = UIColor(red: 0.04, green: 0.14, blue: 0.20, alpha: 1)
        copperRing.strokeColor = UIColor(red: 0.68, green: 0.36, blue: 0.19, alpha: 1)
        copperRing.lineWidth = 5
        node.addChild(copperRing)

        let innerRim = SKShapeNode(circleOfRadius: 26)
        innerRim.position = rearHousing.position
        innerRim.fillColor = UIColor(red: 0.025, green: 0.10, blue: 0.15, alpha: 1)
        innerRim.strokeColor = UIColor(red: 0.18, green: 0.54, blue: 0.59, alpha: 0.9)
        innerRim.lineWidth = 2
        node.addChild(innerRim)

        let rotor = SKNode()
        rotor.position = rearHousing.position
        rotor.zPosition = 3
        for bladeIndex in 0..<5 {
            let bladePath = CGMutablePath()
            bladePath.move(to: CGPoint(x: -3.5, y: 4))
            bladePath.addCurve(
                to: CGPoint(x: 2, y: 23),
                control1: CGPoint(x: -10, y: 12),
                control2: CGPoint(x: -8, y: 22)
            )
            bladePath.addCurve(
                to: CGPoint(x: 4.5, y: 5),
                control1: CGPoint(x: 10, y: 20),
                control2: CGPoint(x: 9, y: 10)
            )
            bladePath.closeSubpath()
            let blade = SKShapeNode(path: bladePath)
            blade.zRotation = CGFloat(bladeIndex) * (.pi * 2 / 5)
            blade.fillColor = UIColor(red: 0.20, green: 0.68, blue: 0.72, alpha: 0.96)
            blade.strokeColor = UIColor(red: 0.50, green: 0.90, blue: 0.88, alpha: 0.34)
            blade.lineWidth = 0.8
            rotor.addChild(blade)
        }
        let rotorDirection: CGFloat = onLeft ? 1 : -1
        rotor.run(.repeatForever(.rotate(
            byAngle: rotorDirection * .pi * 2,
            duration: 3.2 + Double(index) * 0.45
        )))
        node.addChild(rotor)

        let hubShadow = SKShapeNode(circleOfRadius: 9)
        hubShadow.position = CGPoint(x: rotor.position.x + 1.5, y: rotor.position.y - 2)
        hubShadow.zPosition = 3.5
        hubShadow.fillColor = UIColor.black.withAlphaComponent(0.44)
        hubShadow.strokeColor = .clear
        node.addChild(hubShadow)

        let core = SKShapeNode(circleOfRadius: 7)
        core.position = rotor.position
        core.zPosition = 4
        core.fillColor = UIColor(red: 0.46, green: 0.95, blue: 0.92, alpha: 1)
        core.strokeColor = UIColor(red: 0.83, green: 0.48, blue: 0.24, alpha: 1)
        core.lineWidth = 2
        core.glowWidth = 3
        core.run(.repeatForever(.sequence([
            .scale(to: 1.13, duration: 0.8),
            .scale(to: 0.92, duration: 0.8)
        ])))
        node.addChild(core)

        let pressureLight = SKShapeNode(circleOfRadius: 3.5)
        pressureLight.position = CGPoint(x: facing * 31, y: 17)
        pressureLight.zPosition = 5
        pressureLight.fillColor = UIColor(red: 1.0, green: 0.55, blue: 0.26, alpha: 1)
        pressureLight.strokeColor = .clear
        pressureLight.glowWidth = 2
        pressureLight.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.28, duration: 0.45 + Double(index) * 0.08),
            .fadeAlpha(to: 1.0, duration: 0.45 + Double(index) * 0.08)
        ])))
        node.addChild(pressureLight)

        node.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 2, duration: 1.6 + Double(index) * 0.12),
            .moveBy(x: 0, y: -2, duration: 1.6 + Double(index) * 0.12)
        ])))
        return node
    }

    private func makeFluxPylon(index: Int, pointsUp: Bool) -> SKNode {
        let node = SKNode()
        let orientation: CGFloat = pointsUp ? 1 : -1

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 50, height: 16))
        shadow.position = CGPoint(x: 0, y: -orientation * 20)
        shadow.fillColor = UIColor.black.withAlphaComponent(0.34)
        shadow.strokeColor = .clear
        node.addChild(shadow)

        let base = SKShapeNode(rectOf: CGSize(width: 42, height: 36), cornerRadius: 11)
        base.fillColor = UIColor(red: 0.08, green: 0.20, blue: 0.29, alpha: 0.98)
        base.strokeColor = UIColor(red: 0.30, green: 0.76, blue: 0.76, alpha: 0.94)
        base.lineWidth = 3
        node.addChild(base)

        let mast = SKShapeNode(rectOf: CGSize(width: 10, height: 48), cornerRadius: 5)
        mast.position = CGPoint(x: 0, y: orientation * 31)
        mast.fillColor = UIColor(red: 0.70, green: 0.48, blue: 0.24, alpha: 1)
        mast.strokeColor = UIColor(red: 0.22, green: 0.18, blue: 0.25, alpha: 1)
        mast.lineWidth = 2
        node.addChild(mast)

        let orbit = SKNode()
        orbit.position = CGPoint(x: 0, y: orientation * 56)
        for dotIndex in 0..<3 {
            let dot = SKShapeNode(circleOfRadius: dotIndex == 0 ? 5 : 3.5)
            dot.position = CGPoint(x: 16, y: 0)
            dot.zRotation = CGFloat(dotIndex) * (.pi * 2 / 3)
            let carrier = SKNode()
            carrier.zRotation = CGFloat(dotIndex) * (.pi * 2 / 3)
            carrier.addChild(dot)
            dot.fillColor = dotIndex == 0
                ? UIColor(red: 1.0, green: 0.65, blue: 0.25, alpha: 1)
                : UIColor(red: 0.29, green: 0.96, blue: 0.92, alpha: 1)
            dot.strokeColor = .clear
            dot.glowWidth = 2.5
            orbit.addChild(carrier)
        }
        orbit.run(.repeatForever(.rotate(
            byAngle: (index.isMultiple(of: 2) ? 1 : -1) * .pi * 2,
            duration: 2.8 + Double(index % 3) * 0.35
        )))
        node.addChild(orbit)

        let pulse = SKShapeNode(circleOfRadius: 5.5)
        pulse.position = orbit.position
        pulse.fillColor = UIColor(red: 0.87, green: 1.0, blue: 0.74, alpha: 1)
        pulse.strokeColor = .clear
        pulse.glowWidth = 4
        pulse.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.42, duration: 0.55),
            .fadeAlpha(to: 1.0, duration: 0.55)
        ])))
        node.addChild(pulse)
        return node
    }

    private func makeBackgroundSliceSprite(
        from texture: SKTexture,
        imageSize: CGSize,
        cropRectTopLeft: CGRect,
        renderSize: CGSize
    ) -> SKSpriteNode? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let normalizedRect = CGRect(
            x: cropRectTopLeft.minX / imageSize.width,
            y: (imageSize.height - cropRectTopLeft.maxY) / imageSize.height,
            width: cropRectTopLeft.width / imageSize.width,
            height: cropRectTopLeft.height / imageSize.height
        )

        guard normalizedRect.width > 0, normalizedRect.height > 0 else { return nil }

        let sliceTexture = SKTexture(rect: normalizedRect, in: texture)
        sliceTexture.filteringMode = .linear
        return SKSpriteNode(texture: sliceTexture, size: renderSize)
    }

    private func makeMeasurementBlock() -> SKNode {
        let size = CGSize(width: GameConfig.tileSize, height: GameConfig.tileSize)
        let block = SKShapeNode(rectOf: size, cornerRadius: 3)
        block.fillColor = UIColor(red: 0.63, green: 0.42, blue: 0.20, alpha: 0.92)
        block.strokeColor = UIColor(red: 0.29, green: 0.16, blue: 0.07, alpha: 0.95)
        block.lineWidth = 2

        let container = SKNode()
        container.addChild(block)

        let highlight = SKShapeNode(rectOf: CGSize(width: size.width * 0.62, height: size.height * 0.18), cornerRadius: 2)
        highlight.position = CGPoint(x: 0, y: size.height * 0.20)
        highlight.fillColor = UIColor.white.withAlphaComponent(0.20)
        highlight.strokeColor = .clear
        container.addChild(highlight)

        return container
    }

    private func makeMeasurementBlocks() -> SKNode {
        let container = SKNode()
        container.zPosition = 4

        let horizontalY = playableRect.minY + GameConfig.tileSize * 0.5
        let verticalX = playableRect.minX + GameConfig.tileSize * 0.5

        for index in 0..<Int(GameConfig.mapColumns) {
            let block = makeMeasurementBlock()
            block.position = CGPoint(
                x: playableRect.minX + GameConfig.tileSize * (CGFloat(index) + 0.5),
                y: horizontalY
            )
            container.addChild(block)
        }

        for index in 0..<Int(GameConfig.mapRows) {
            let block = makeMeasurementBlock()
            block.position = CGPoint(
                x: verticalX,
                y: playableRect.minY + GameConfig.tileSize * (CGFloat(index) + 0.5)
            )
            container.addChild(block)
        }

        return container
    }

    private func makeGridPath(in rect: CGRect, spacing: CGFloat) -> CGPath {
        let path = CGMutablePath()

        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }

        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }

        return path
    }

    private func makeTilePath(in rect: CGRect, tileSize: CGFloat, inset: CGFloat) -> CGPath {
        let path = CGMutablePath()
        var y = rect.minY

        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                let tileRect = CGRect(
                    x: x + inset,
                    y: y + inset,
                    width: tileSize - inset * 2,
                    height: tileSize - inset * 2
                )
                path.addRoundedRect(in: tileRect, cornerWidth: 8, cornerHeight: 8)
                x += tileSize
            }
            y += tileSize
        }

        return path
    }

    private func makeTintBands(in rect: CGRect) -> SKNode {
        let container = SKNode()
        container.zPosition = -6.5

        let centerBand = SKShapeNode(rect: CGRect(x: -rect.width * 0.18, y: rect.minY, width: rect.width * 0.36, height: rect.height))
        centerBand.fillColor = UIColor(red: 0.81, green: 0.44, blue: 0.55, alpha: 0.22)
        centerBand.strokeColor = .clear
        container.addChild(centerBand)

        let leftBand = SKShapeNode(rect: CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.16, height: rect.height))
        leftBand.fillColor = UIColor(red: 0.43, green: 0.18, blue: 0.28, alpha: 0.34)
        leftBand.strokeColor = .clear
        container.addChild(leftBand)

        let rightBand = SKShapeNode(rect: CGRect(x: rect.maxX - rect.width * 0.16, y: rect.minY, width: rect.width * 0.16, height: rect.height))
        rightBand.fillColor = UIColor(red: 0.43, green: 0.18, blue: 0.28, alpha: 0.34)
        rightBand.strokeColor = .clear
        container.addChild(rightBand)

        return container
    }


    private func makeEdgeGreens(in rect: CGRect) -> SKNode {
        let container = SKNode()
        container.zPosition = -6.4

        let stripWidth = rect.width * 0.06
        for x in [rect.minX + stripWidth / 2, rect.maxX - stripWidth / 2] {
            let strip = SKShapeNode(rectOf: CGSize(width: stripWidth, height: rect.height))
            strip.position = CGPoint(x: x, y: 0)
            strip.fillColor = UIColor(red: 0.27, green: 0.58, blue: 0.24, alpha: 0.95)
            strip.strokeColor = UIColor(red: 0.14, green: 0.36, blue: 0.16, alpha: 1)
            strip.lineWidth = 3
            container.addChild(strip)
        }

        return container
    }

    private func makeSideDecor(in rect: CGRect) -> SKNode {
        let container = SKNode()
        container.zPosition = -6.3

        let wallWidth = rect.width * 0.08
        let leftWall = SKShapeNode(rect: CGRect(x: rect.minX, y: rect.minY, width: wallWidth, height: rect.height))
        leftWall.fillColor = UIColor(red: 0.86, green: 0.25, blue: 0.36, alpha: 0.96)
        leftWall.strokeColor = .clear
        container.addChild(leftWall)

        let rightWall = SKShapeNode(rect: CGRect(x: rect.maxX - wallWidth, y: rect.minY, width: wallWidth, height: rect.height))
        rightWall.fillColor = UIColor(red: 0.86, green: 0.25, blue: 0.36, alpha: 0.96)
        rightWall.strokeColor = .clear
        container.addChild(rightWall)

        for side in [-1.0, 1.0] {
            for index in 0..<7 {
                let orb = SKShapeNode(circleOfRadius: 14)
                orb.position = CGPoint(
                    x: side < 0 ? rect.minX + wallWidth * 0.52 : rect.maxX - wallWidth * 0.52,
                    y: rect.maxY - 180 - CGFloat(index) * 240
                )
                orb.fillColor = index.isMultiple(of: 2)
                    ? UIColor(red: 0.33, green: 0.82, blue: 0.97, alpha: 0.95)
                    : UIColor(red: 1.0, green: 0.84, blue: 0.36, alpha: 0.95)
                orb.strokeColor = UIColor.white.withAlphaComponent(0.25)
                orb.lineWidth = 2
                container.addChild(orb)
            }
        }

        return container
    }

    private func makeMachineDecor(in rect: CGRect) -> SKNode {
        let container = SKNode()
        container.zPosition = -6.15

        func makeMachine(onLeft: Bool) -> SKNode {
            let node = SKNode()
            let direction: CGFloat = onLeft ? -1 : 1
            let baseX = onLeft ? rect.minX + 86 : rect.maxX - 86

            let body = SKShapeNode(rectOf: CGSize(width: 128, height: 220), cornerRadius: 34)
            body.position = CGPoint(x: baseX, y: rect.height * 0.23)
            body.fillColor = UIColor(red: 0.74, green: 0.20, blue: 0.44, alpha: 0.96)
            body.strokeColor = UIColor(red: 0.97, green: 0.66, blue: 0.32, alpha: 0.8)
            body.lineWidth = 6
            node.addChild(body)

            let tube = SKShapeNode(rectOf: CGSize(width: 40, height: 180), cornerRadius: 20)
            tube.position = CGPoint(x: baseX - direction * 28, y: rect.height * 0.18)
            tube.zRotation = direction * 0.22
            tube.fillColor = UIColor(red: 0.49, green: 0.26, blue: 0.78, alpha: 0.96)
            tube.strokeColor = UIColor(red: 0.69, green: 0.94, blue: 0.98, alpha: 0.82)
            tube.lineWidth = 5
            node.addChild(tube)

            let lens = SKShapeNode(circleOfRadius: 30)
            lens.position = CGPoint(x: baseX + direction * 12, y: rect.height * 0.14)
            lens.fillColor = UIColor(red: 0.89, green: 0.86, blue: 1.0, alpha: 0.95)
            lens.strokeColor = UIColor(red: 0.56, green: 0.92, blue: 1.0, alpha: 1)
            lens.lineWidth = 5
            node.addChild(lens)

            let cablePath = CGMutablePath()
            cablePath.move(to: CGPoint(x: baseX + direction * 6, y: rect.height * 0.04))
            cablePath.addCurve(
                to: CGPoint(x: baseX + direction * 52, y: rect.height * -0.24),
                control1: CGPoint(x: baseX + direction * 34, y: rect.height * -0.02),
                control2: CGPoint(x: baseX + direction * 12, y: rect.height * -0.18)
            )
            let cable = SKShapeNode(path: cablePath)
            cable.strokeColor = UIColor(red: 0.36, green: 0.84, blue: 0.79, alpha: 0.95)
            cable.lineWidth = 10
            cable.lineCap = .round
            node.addChild(cable)

            let orb = SKShapeNode(circleOfRadius: 24)
            orb.position = CGPoint(x: baseX + direction * 60, y: rect.height * -0.28)
            orb.fillColor = UIColor(red: 0.20, green: 0.46, blue: 0.88, alpha: 0.95)
            orb.strokeColor = UIColor.white.withAlphaComponent(0.45)
            orb.lineWidth = 4
            node.addChild(orb)

            return node
        }

        container.addChild(makeMachine(onLeft: true))
        container.addChild(makeMachine(onLeft: false))
        return container
    }

    private func makeAccentPads(in rect: CGRect) -> SKNode {
        let container = SKNode()
        container.zPosition = -6.2

        let padSpecs: [(CGPoint, CGSize, UIColor)] = [
            (CGPoint(x: -rect.width * 0.18, y: rect.height * 0.22), CGSize(width: 120, height: 74), UIColor(red: 0.29, green: 0.80, blue: 0.89, alpha: 0.92)),
            (CGPoint(x: rect.width * 0.18, y: -rect.height * 0.14), CGSize(width: 118, height: 74), UIColor(red: 0.29, green: 0.80, blue: 0.89, alpha: 0.92)),
            (CGPoint(x: 0, y: rect.height * 0.36), CGSize(width: 138, height: 26), UIColor(red: 0.92, green: 0.80, blue: 0.43, alpha: 0.88)),
            (CGPoint(x: 0, y: -rect.height * 0.34), CGSize(width: 138, height: 26), UIColor(red: 0.92, green: 0.80, blue: 0.43, alpha: 0.88))
        ]

        for (position, size, color) in padSpecs {
            let pad = SKShapeNode(rectOf: size, cornerRadius: 10)
            pad.position = position
            pad.fillColor = color
            pad.strokeColor = color.withAlphaComponent(0.55)
            pad.lineWidth = 2
            container.addChild(pad)
        }

        return container
    }

    private func makeGroundPatches(in rect: CGRect) -> SKNode {
        let container = SKNode()
        container.zPosition = -5.6

        let specs: [(CGPoint, CGSize, CGFloat, UIColor)] = [
            (CGPoint(x: -rect.width * 0.26, y: rect.height * 0.18), CGSize(width: 220, height: 120), 0.18, UIColor(red: 0.42, green: 0.18, blue: 0.27, alpha: 0.34)),
            (CGPoint(x: rect.width * 0.24, y: rect.height * 0.08), CGSize(width: 180, height: 104), -0.24, UIColor(red: 0.72, green: 0.37, blue: 0.50, alpha: 0.20)),
            (CGPoint(x: -rect.width * 0.22, y: -rect.height * 0.12), CGSize(width: 210, height: 116), -0.12, UIColor(red: 0.70, green: 0.33, blue: 0.46, alpha: 0.22)),
            (CGPoint(x: rect.width * 0.20, y: -rect.height * 0.24), CGSize(width: 230, height: 132), 0.16, UIColor(red: 0.39, green: 0.16, blue: 0.24, alpha: 0.36))
        ]

        for (position, size, rotation, color) in specs {
            let patch = SKShapeNode(rectOf: size, cornerRadius: 28)
            patch.position = position
            patch.zRotation = rotation
            patch.fillColor = color
            patch.strokeColor = UIColor.white.withAlphaComponent(0.06)
            patch.lineWidth = 2
            container.addChild(patch)
        }

        return container
    }

    private func makeCheckerTiles(in rect: CGRect) -> SKNode {
        let container = SKNode()
        container.zPosition = -5.4

        let tileSize: CGFloat = 128
        var row = 0
        var y = rect.minY

        while y < rect.maxY {
            var column = 0
            var x = rect.minX

            while x < rect.maxX {
                if (row + column).isMultiple(of: 2) {
                    let tile = SKShapeNode(rect: CGRect(x: x, y: y, width: tileSize, height: tileSize))
                    tile.fillColor = UIColor(red: 0.47, green: 0.20, blue: 0.30, alpha: 0.22)
                    tile.strokeColor = .clear
                    container.addChild(tile)
                }
                column += 1
                x += tileSize
            }

            row += 1
            y += tileSize
        }

        return container
    }

    private func makeCenterArena(in rect: CGRect) -> SKNode {
        let container = SKNode()
        container.zPosition = -2.95

        let ring = SKShapeNode(circleOfRadius: min(rect.width, rect.height) * 0.16)
        ring.fillColor = UIColor.clear
        ring.strokeColor = UIColor(red: 0.74, green: 0.96, blue: 0.93, alpha: 0.72)
        ring.lineWidth = 8
        container.addChild(ring)

        let innerRing = SKShapeNode(circleOfRadius: min(rect.width, rect.height) * 0.085)
        innerRing.fillColor = UIColor(red: 0.39, green: 0.17, blue: 0.29, alpha: 0.9)
        innerRing.strokeColor = UIColor(red: 0.87, green: 0.93, blue: 0.56, alpha: 0.86)
        innerRing.lineWidth = 5
        container.addChild(innerRing)

        let offsets: [CGPoint] = [
            CGPoint(x: 0, y: 116),
            CGPoint(x: -108, y: -42),
            CGPoint(x: 108, y: -42)
        ]
        let fills = [
            UIColor(red: 0.43, green: 0.25, blue: 0.42, alpha: 0.94),
            UIColor(red: 0.45, green: 0.24, blue: 0.36, alpha: 0.94),
            UIColor(red: 0.47, green: 0.23, blue: 0.39, alpha: 0.94)
        ]
        let accentColors = [
            UIColor(red: 0.52, green: 0.92, blue: 0.96, alpha: 0.92),
            UIColor(red: 0.89, green: 0.83, blue: 0.42, alpha: 0.92),
            UIColor(red: 0.86, green: 0.52, blue: 0.88, alpha: 0.92)
        ]

        for index in 0..<offsets.count {
            let flower = SKShapeNode(path: makeBlobPath(size: CGSize(width: 128, height: 102)))
            flower.position = offsets[index]
            flower.fillColor = fills[index]
            flower.strokeColor = UIColor(red: 0.83, green: 0.80, blue: 0.58, alpha: 0.8)
            flower.lineWidth = 4
            container.addChild(flower)

            let core = SKShapeNode(circleOfRadius: 12)
            core.position = CGPoint(x: offsets[index].x + (index == 0 ? 0 : (index == 1 ? -18 : 18)), y: offsets[index].y + (index == 0 ? 12 : -6))
            core.fillColor = accentColors[index]
            core.strokeColor = UIColor.white.withAlphaComponent(0.3)
            core.lineWidth = 2
            container.addChild(core)
        }

        return container
    }

    private func makeBlobPath(size: CGSize) -> CGPath {
        let w = size.width
        let h = size.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -w * 0.46, y: -h * 0.10))
        path.addCurve(to: CGPoint(x: -w * 0.18, y: h * 0.42),
                      control1: CGPoint(x: -w * 0.54, y: h * 0.18),
                      control2: CGPoint(x: -w * 0.38, y: h * 0.48))
        path.addCurve(to: CGPoint(x: w * 0.22, y: h * 0.38),
                      control1: CGPoint(x: -w * 0.02, y: h * 0.34),
                      control2: CGPoint(x: w * 0.10, y: h * 0.52))
        path.addCurve(to: CGPoint(x: w * 0.48, y: -h * 0.02),
                      control1: CGPoint(x: w * 0.44, y: h * 0.26),
                      control2: CGPoint(x: w * 0.56, y: h * 0.10))
        path.addCurve(to: CGPoint(x: w * 0.18, y: -h * 0.42),
                      control1: CGPoint(x: w * 0.42, y: -h * 0.24),
                      control2: CGPoint(x: w * 0.34, y: -h * 0.46))
        path.addCurve(to: CGPoint(x: -w * 0.26, y: -h * 0.40),
                      control1: CGPoint(x: 0, y: -h * 0.34),
                      control2: CGPoint(x: -w * 0.16, y: -h * 0.52))
        path.addCurve(to: CGPoint(x: -w * 0.46, y: -h * 0.10),
                      control1: CGPoint(x: -w * 0.44, y: -h * 0.34),
                      control2: CGPoint(x: -w * 0.56, y: -h * 0.20))
        path.closeSubpath()
        return path
    }

    private func makeDirectionMarks(in rect: CGRect) -> SKNode {
        let container = SKNode()
        container.zPosition = -2.8

        for y in stride(from: rect.minY + 180, through: rect.maxY - 180, by: 220) {
            let markerPath = CGMutablePath()
            markerPath.move(to: CGPoint(x: -42, y: y))
            markerPath.addLine(to: CGPoint(x: 42, y: y))
            markerPath.move(to: CGPoint(x: 18, y: y - 14))
            markerPath.addLine(to: CGPoint(x: 42, y: y))
            markerPath.addLine(to: CGPoint(x: 18, y: y + 14))

            let marker = SKShapeNode(path: markerPath)
            marker.strokeColor = UIColor(red: 0.80, green: 0.86, blue: 0.52, alpha: 0.30)
            marker.lineWidth = 4
            container.addChild(marker)
        }

        return container
    }

    private func makeLaneMarkerPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let centerBandWidth = rect.width * 0.30
        let centerBandRect = CGRect(
            x: -centerBandWidth / 2,
            y: rect.minY + 100,
            width: centerBandWidth,
            height: rect.height - 200
        )

        path.addRoundedRect(in: centerBandRect, cornerWidth: 30, cornerHeight: 30)

        let ringRadius = min(rect.width, rect.height) * 0.10
        path.addEllipse(in: CGRect(x: -ringRadius, y: -ringRadius, width: ringRadius * 2, height: ringRadius * 2))

        let topRingY = rect.maxY * 0.52
        path.addEllipse(in: CGRect(x: -ringRadius * 0.95, y: topRingY - ringRadius, width: ringRadius * 1.9, height: ringRadius * 1.9))

        let bottomRingY = rect.minY * 0.52
        path.addEllipse(in: CGRect(x: -ringRadius * 0.95, y: bottomRingY - ringRadius, width: ringRadius * 1.9, height: ringRadius * 1.9))

        for y in stride(from: rect.minY + 220, through: rect.maxY - 220, by: 340) {
            path.move(to: CGPoint(x: -28, y: y))
            path.addLine(to: CGPoint(x: 28, y: y))
        }

        return path
    }

    private func makeAnchorMarkers(in rect: CGRect) -> [SKNode] {
        let positions = stride(from: rect.minY + 180, through: rect.maxY - 180, by: 360).flatMap { y in
            stride(from: rect.minX + 180, through: rect.maxX - 180, by: 360).map { x in
                CGPoint(x: x, y: y)
            }
        }

        return positions.enumerated().map { index, position in
            let marker = SKNode()
            marker.position = position
            marker.zPosition = -2

            let radius: CGFloat = index.isMultiple(of: 2) ? 20 : 14
            let disc = SKShapeNode(circleOfRadius: radius)
            disc.fillColor = UIColor(red: 0.47, green: 0.23, blue: 0.33, alpha: 0.34)
            disc.strokeColor = UIColor(red: 0.29, green: 0.12, blue: 0.19, alpha: 0.58)
            disc.lineWidth = 2
            marker.addChild(disc)

            let crossPath = CGMutablePath()
            crossPath.move(to: CGPoint(x: -radius - 8, y: 0))
            crossPath.addLine(to: CGPoint(x: radius + 8, y: 0))
            crossPath.move(to: CGPoint(x: 0, y: -radius - 8))
            crossPath.addLine(to: CGPoint(x: 0, y: radius + 8))

            let cross = SKShapeNode(path: crossPath)
            cross.strokeColor = UIColor(red: 0.27, green: 0.12, blue: 0.18, alpha: 0.42)
            cross.lineWidth = 2
            marker.addChild(cross)

            return marker
        }
    }

    private func updateCameraScale() {
        guard size.height > 0 else { return }
        gameCamera.xScale = currentCameraScaleX
        gameCamera.yScale = currentCameraScaleY
    }

    private func updateCameraPosition() {
        let visibleHeight = currentCameraVisibleHeight
        let distanceFromBottom = player.position.y - (playableRect.minY + GameConfig.playerCollisionRadius)
        let blendDistance = GameConfig.cameraBottomBlendDistanceTiles * GameConfig.tileSize
        let bottomBlend = max(0, min(1, 1 - distanceFromBottom / max(1, blendDistance)))
        let visibleTilesAbovePlayer =
            GameConfig.cameraTilesVisibleAbovePlayer +
            (GameConfig.cameraTilesVisibleAbovePlayerAtBottom - GameConfig.cameraTilesVisibleAbovePlayer) * bottomBlend
        let verticalFocusOffset = visibleTilesAbovePlayer * GameConfig.tileSize - visibleHeight / 2
        let shakeOffset: CGPoint
        if screenShakeTimeRemaining > 0 {
            shakeOffset = CGPoint(
                x: CGFloat.random(in: -GameConfig.shakeAmplitude...GameConfig.shakeAmplitude),
                y: CGFloat.random(in: -GameConfig.shakeAmplitude...GameConfig.shakeAmplitude)
            )
        } else {
            shakeOffset = .zero
        }

        if autoWallTest && !autoWallCapture {
            gameCamera.position = CGPoint(
                x: playableRect.midX + shakeOffset.x,
                y: playableRect.midY + shakeOffset.y
            )
            return
        }

        if autoAttackTest {
            gameCamera.position = CGPoint(
                x: playableRect.midX + shakeOffset.x,
                y: playableRect.midY + GameConfig.tileSize * 0.2 + shakeOffset.y
            )
            return
        }

        gameCamera.position = CGPoint(
            x: playableRect.midX + shakeOffset.x,
            y: player.position.y + verticalFocusOffset + shakeOffset.y
        )
    }

    private func updateCameraShake(deltaTime: TimeInterval) {
        screenShakeTimeRemaining = max(0, screenShakeTimeRemaining - deltaTime)
    }

    private func updateBullets(deltaTime: TimeInterval) {
        var survivors: [BulletNode] = []
        var spawnedFragments: [BulletNode] = []
        survivors.reserveCapacity(bullets.count)

        for bullet in bullets {
            let outcome = bullet.update(deltaTime: deltaTime)

            if case .active = outcome,
               !autoAttackTest,
               let contactExplosion = bullet.contactExplosionSpec(),
               bullet.intersectsPlayer(at: player.hitCenterWorld) {
                let fragments = handleExplosion(contactExplosion, from: bullet)
                spawnedFragments.append(contentsOf: fragments)
                continue
            }

            let didHitPlayer = detectHit(for: bullet)

            if didHitPlayer {
                continue
            }

            switch outcome {
            case .active:
                survivors.append(bullet)
            case .expired:
                dodgedCount += 1
                bullet.removeFromParent()
            case .explode(let explosion):
                let fragments = handleExplosion(explosion, from: bullet)
                spawnedFragments.append(contentsOf: fragments)
            }
        }

        bullets = survivors + spawnedFragments
    }

    private func updatePendingHyperchargeExplosions(deltaTime: TimeInterval) {
        guard !pendingHyperchargeExplosions.isEmpty else { return }

        var waiting: [PendingHyperchargeExplosion] = []
        var spawnedFragments: [BulletNode] = []
        waiting.reserveCapacity(pendingHyperchargeExplosions.count)

        for var pending in pendingHyperchargeExplosions {
            pending.timeRemaining -= deltaTime
            if pending.timeRemaining > 0 {
                waiting.append(pending)
                continue
            }

            pending.coreNode.removeFromParent()
            spawnedFragments.append(
                contentsOf: resolveExplosion(pending.explosion)
            )
        }

        pendingHyperchargeExplosions = waiting
        bullets.append(contentsOf: spawnedFragments)
    }

    private func detectHit(for bullet: BulletNode) -> Bool {
        if autoAttackTest || (GameConfig.debugCornerAttackTestEnabled
            && !GameConfig.debugCornerDamageEnabled) {
            return false
        }
        if bullet.isTimedParent {
            return false
        }
        if !bullet.canDealContactDamage {
            return false
        }
        guard !bullet.hasDealtDamage else { return false }
        guard bullet.intersectsPlayer(at: player.hitCenterWorld) else { return false }

        bullet.registerHit()
        bullet.removeFromParent()
        hitCount += 1
        if GameConfig.debugProjectileLoggingEnabled {
            print("PLAYER HIT projectile count=\(hitCount)")
        }
        screenShakeTimeRemaining = GameConfig.shakeDuration
        playHitFeedback()

        let isDead = player.takeDamage(bullet.damage)
        if isDead {
            endGame()
        }

        return true
    }

    private func spawnBullet(
        toward targetPoint: CGPoint,
        variant: ThornAttackVariant
    ) {
        let direction = CGVector(
            dx: targetPoint.x - enemy.position.x,
            dy: targetPoint.y - enemy.position.y
        ).normalized
        let rightHandOffset = CGVector(dx: direction.dy, dy: -direction.dx)
        let spawnPoint = CGPoint(
            x: enemy.position.x
                + direction.dx * (GameConfig.enemyVisualRadius + GameConfig.thornBallSpawnInset)
                + rightHandOffset.dx * (GameConfig.tileSize * 0.22),
            y: enemy.position.y
                + direction.dy * (GameConfig.enemyVisualRadius + GameConfig.thornBallSpawnInset)
                + rightHandOffset.dy * (GameConfig.tileSize * 0.22)
        )
        let bullet = BulletNode.thornBall(
            direction: direction,
            variant: variant
        )
        bullet.position = spawnPoint
        bullet.zPosition = 25
        bullets.append(bullet)
        addChild(bullet)
    }

    private func scheduleAutoAttackCaptures() {
        guard autoAttackCapture else { return }
        currentAttackCaptureID += 1
        autoAttackCaptureSchedule = autoAttackCaptureMoments.enumerated().map { offset, moment in
            (index: offset + 1, triggerTime: survivalTime + moment)
        }
        appendAutoAttackLog("THROW id=\(currentAttackCaptureID) start=\(String(format: "%.3f", survivalTime))")
    }

    private func runAutoAttackCaptureIfNeeded() {
        guard autoAttackCapture, !autoAttackCaptureSchedule.isEmpty else { return }

        while let next = autoAttackCaptureSchedule.first, survivalTime >= next.triggerTime {
            autoAttackCaptureSchedule.removeFirst()
            captureAutoAttackFrame(index: next.index)
        }
    }

    private func captureAutoAttackFrame(index: Int) {
        guard let view = self.view else { return }

        let shotID = currentAttackCaptureID
        let timeStamp = survivalTime
        Task { @MainActor [weak self] in
            guard let self else { return }
            let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
            let image = renderer.image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            guard let data = image.pngData() else { return }
            let fileName = String(
                format: "shot_%02d_frame_%02d_t_%05.2f.png",
                shotID,
                index,
                timeStamp
            )
            let fileURL = self.autoAttackCaptureDirectoryURL.appendingPathComponent(fileName)
            try? data.write(to: fileURL)
            self.appendAutoAttackLog("CAPTURE saved=\(fileName)")
        }
    }

    private func appendAutoAttackLog(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: autoAttackLogURL.path),
           let handle = try? FileHandle(forWritingTo: autoAttackLogURL) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
            }
            return
        }

        try? data.write(to: autoAttackLogURL)
    }

    private func constrainEnemyToUpperLane() {
        let visibleWidth = gameplayReferenceVisibleWidth
        let visibleHeight = gameplayReferenceVisibleHeight
        let laneRect = CGRect(
            x: player.position.x + visibleWidth * GameConfig.enemyAnchorHorizontalOffsetRatio - visibleWidth * GameConfig.enemyHorizontalLeashRatio,
            y: player.position.y + visibleHeight * GameConfig.enemyMinVerticalOffsetRatio,
            width: visibleWidth * GameConfig.enemyHorizontalLeashRatio * 2,
            height: visibleHeight * (GameConfig.enemyMaxVerticalOffsetRatio - GameConfig.enemyMinVerticalOffsetRatio)
        ).intersection(
            playableRect.insetBy(dx: GameConfig.enemyCollisionRadius, dy: GameConfig.enemyCollisionRadius)
        )

        guard !laneRect.isNull, !laneRect.isEmpty else { return }
        enemy.position = constrainedArenaPosition(
            enemy.position.clamped(in: laneRect),
            collisionRadius: GameConfig.enemyCollisionRadius
        )
    }

    private var currentCameraScaleX: CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }

        if UIDevice.current.userInterfaceIdiom == .pad {
            // Match Brawl Stars' tablet framing: preserve the authored iPhone
            // render scale, then let the narrower 16:9 tablet viewport crop
            // equal amounts from the left and right. Using the tablet width as
            // the scale reference would squeeze the complete iPhone view into
            // 16:9 and alter the apparent depth and actor proportions.
            let referenceAspectRatio = GameConfig.referenceBattlePixelSize.width
                / GameConfig.referenceBattlePixelSize.height
            let referenceSurfaceWidth = size.height * referenceAspectRatio
            return GameConfig.cameraVisibleWidth / referenceSurfaceWidth
        }

        return GameConfig.cameraVisibleWidth / size.width
    }

    private var currentCameraScaleY: CGFloat {
        guard size.height > 0 else { return 1 }
        return GameConfig.cameraVisibleHeight / size.height
    }

    private var currentCameraVisibleHeight: CGFloat {
        GameConfig.cameraVisibleHeight
    }

    /// Camera cropping is presentation-only. Enemy steering, projectile
    /// lifetime, and every gameplay calculation continue to use the same
    /// device-independent logical view as the approved iPhone tuning.
    private var gameplayReferenceVisibleWidth: CGFloat {
        GameConfig.cameraVisibleWidth
    }

    private var gameplayReferenceVisibleHeight: CGFloat {
        GameConfig.cameraVisibleHeight
    }

    private var currentVisibleRect: CGRect {
        let visibleWidth = gameplayReferenceVisibleWidth
        let visibleHeight = gameplayReferenceVisibleHeight
        return CGRect(
            x: gameCamera.position.x - visibleWidth / 2,
            y: gameCamera.position.y - visibleHeight / 2,
            width: visibleWidth,
            height: visibleHeight
        )
    }

    private func preferredEnemyAnchorPosition() -> CGPoint {
        let visibleWidth = gameplayReferenceVisibleWidth
        let visibleHeight = gameplayReferenceVisibleHeight
        let anchorPoint = CGPoint(
            x: enemyReferencePoint.x + visibleWidth * GameConfig.enemyAnchorHorizontalOffsetRatio,
            y: enemyReferencePoint.y + visibleHeight * GameConfig.enemyAnchorVerticalOffsetRatio
        )
        return constrainedArenaPosition(anchorPoint, collisionRadius: GameConfig.enemyCollisionRadius)
    }

    private func updateEnemyReferencePoint(deltaTime: TimeInterval) {
        let horizontalBlend = min(1, CGFloat(deltaTime) * GameConfig.enemyReferenceFollowRate)
        let verticalBlend = min(1, CGFloat(deltaTime) * (GameConfig.enemyReferenceFollowRate * 0.55))
        let practiceCenter = CGPoint(
            x: playableRect.midX,
            y: min(max(0, playableRect.minY), playableRect.maxY)
        )
        let horizontalTarget = practiceCenter.x
            + (player.position.x - practiceCenter.x) * 0.28
        let verticalInfluence: CGFloat = player.position.y < practiceCenter.y ? 0.05 : 0.20
        let verticalTarget = practiceCenter.y
            + (player.position.y - practiceCenter.y) * verticalInfluence
        enemyReferencePoint = CGPoint(
            x: enemyReferencePoint.x + (horizontalTarget - enemyReferencePoint.x) * horizontalBlend,
            y: enemyReferencePoint.y + (verticalTarget - enemyReferencePoint.y) * verticalBlend
        )
    }

    private func updateWallPressureRecoveryState() {
        guard !autoWallTest, !autoAttackTest else {
            if isWallPressureRecoveryActive {
                isWallPressureRecoveryActive = false
                enemy.setWallRecoveryActive(false)
            }
            return
        }

        let frontWallY = playableRect.minY + GameConfig.playerCollisionRadius
        let distanceFromFrontWall = max(0, player.position.y - frontWallY)
        if isWallPressureRecoveryActive {
            if distanceFromFrontWall >= GameConfig.enemyWallRecoveryReleaseDistance {
                isWallPressureRecoveryActive = false
                enemy.setWallRecoveryActive(false)
            }
        } else if distanceFromFrontWall <= GameConfig.enemyWallRecoveryTriggerDistance {
            isWallPressureRecoveryActive = true
            enemy.setWallRecoveryActive(true)
        }
    }

    private func makeThrowTargetPoint(for shotContext: EnemyNode.ShotContext) -> CGPoint {
        var refinedPoint = CGPoint(
            x: player.position.x + player.velocity.dx * GameConfig.thornBallTargetLeadFactor,
            y: player.position.y + player.velocity.dy * GameConfig.thornBallTargetLeadFactor
        )

        let towardPlayer = CGVector(
            dx: refinedPoint.x - enemy.position.x,
            dy: refinedPoint.y - enemy.position.y
        ).normalized
        let perpendicular = CGVector(dx: towardPlayer.dy, dy: -towardPlayer.dx)
        let side: CGFloat = Bool.random() ? 1 : -1
        let lateralOffset: CGFloat
        switch shotContext.aimStyle {
        case .direct:
            lateralOffset = 0
        case .smallOffset:
            lateralOffset = CGFloat.random(in: GameConfig.enemySmallAimOffsetRange) * side
        case .largeOffset:
            lateralOffset = CGFloat.random(in: GameConfig.enemyLargeAimOffsetRange) * side
        }
        refinedPoint.x += perpendicular.dx * lateralOffset
        refinedPoint.y += perpendicular.dy * lateralOffset

        if GameConfig.debugProjectileTargetOffsetX != 0 || GameConfig.debugProjectileTargetOffsetY != 0 {
            refinedPoint.x += GameConfig.debugProjectileTargetOffsetX
            refinedPoint.y += GameConfig.debugProjectileTargetOffsetY
        }
        return constrainedArenaPosition(
            refinedPoint,
            collisionRadius: GameConfig.playerCollisionRadius
        )
    }

    private func handleExplosion(_ explosion: ExplosionSpec, from bullet: BulletNode) -> [BulletNode] {
        bullet.removeFromParent()
        let fragments = resolveExplosion(explosion)

        if explosion.variant == .hypercharge {
            let coreNode = spawnHyperchargeCore(at: explosion.position)
            pendingHyperchargeExplosions.append(
                PendingHyperchargeExplosion(
                    timeRemaining: GameConfig.hyperchargeSecondExplosionDelay,
                    explosion: explosion,
                    coreNode: coreNode
                )
            )
        }

        return fragments
    }

    private func resolveExplosion(_ explosion: ExplosionSpec) -> [BulletNode] {
        applySplashDamage(
            at: explosion.damagePosition,
            radius: explosion.splashRadius,
            damage: explosion.splashDamage
        )
        spawnExplosionEffect(
            at: explosion.position,
            variant: explosion.variant
        )
        if GameConfig.debugProjectileLoggingEnabled {
            print(
                "EXPLODE pos=(\(Int(explosion.position.x)),\(Int(explosion.position.y))) "
                + "damagePos=(\(Int(explosion.damagePosition.x)),\(Int(explosion.damagePosition.y))) "
                + "player=(\(Int(player.position.x)),\(Int(player.position.y))) "
                + "count=\(explosion.fragments.count)"
            )
        }

        var fragments: [BulletNode] = []
        fragments.reserveCapacity(explosion.fragments.count)
        for (index, fragmentSpec) in explosion.fragments.enumerated() {
            let fragment = BulletNode.thornShard(
                direction: fragmentSpec.direction,
                angularVelocity: fragmentSpec.angularVelocity,
                keyframes: fragmentSpec.keyframes,
                variant: explosion.variant
            )
            fragment.position = CGPoint(
                x: explosion.position.x,
                y: explosion.position.y
            )
            fragment.zPosition = 27
            fragment.primeSpawnPose()
            fragments.append(fragment)
            addChild(fragment)
            if GameConfig.debugProjectileLoggingEnabled,
               let end = fragmentSpec.keyframes.last {
                print(
                    "FRAGMENT \(index) endPolar=(r:\(Int(end.radius)), sweep:\(Int(end.sweepDegrees))) dir=(\(String(format: "%.2f", fragmentSpec.direction.dx)),\(String(format: "%.2f", fragmentSpec.direction.dy)))"
                )
            }
        }
        return fragments
    }

    private func applySplashDamage(at position: CGPoint, radius: CGFloat, damage: CGFloat) {
        if autoAttackTest || (GameConfig.debugCornerAttackTestEnabled
            && !GameConfig.debugCornerDamageEnabled) {
            return
        }
        let hitCenter = player.hitCenterWorld
        let deltaX = hitCenter.x - position.x
        let deltaY = hitCenter.y - position.y
        let combinedRadius = GameConfig.playerHitRadius + radius
        guard deltaX * deltaX + deltaY * deltaY
            <= combinedRadius * combinedRadius else { return }

        hitCount += 1
        if GameConfig.debugProjectileLoggingEnabled {
            print("PLAYER HIT explosion count=\(hitCount)")
        }
        screenShakeTimeRemaining = GameConfig.shakeDuration
        playHitFeedback()
        let isDead = player.takeDamage(damage)
        if isDead {
            endGame()
        }
    }

    private func spawnExplosionEffect(
        at position: CGPoint,
        variant: ThornAttackVariant
    ) {
        let burst = SKSpriteNode(
            texture: BulletNode.burstTexture,
            size: GameConfig.attackBurstSpriteSize
        )
        if variant == .hypercharge {
            burst.shader = BulletNode.hyperchargePaletteShader
            burst.blendMode = .add
        }
        burst.position = position
        burst.zPosition = 26
        burst.alpha = 0
        burst.setScale(0.34)
        addChild(burst)

        let appear = SKAction.group([
            .scale(to: 1.0, duration: GameConfig.attackBurstAppearDuration),
            .fadeAlpha(to: 0.92, duration: GameConfig.attackBurstAppearDuration)
        ])
        let hold = SKAction.wait(forDuration: GameConfig.attackBurstHoldDuration)
        let disappear = SKAction.group([
            .scale(to: 1.10, duration: GameConfig.attackBurstFadeDuration),
            .fadeOut(withDuration: GameConfig.attackBurstFadeDuration)
        ])
        burst.run(.sequence([appear, hold, disappear, .removeFromParent()]))
    }

    private func spawnHyperchargeCore(at position: CGPoint) -> SKNode {
        let core = SKShapeNode(circleOfRadius: GameConfig.explosionRadius * 0.42)
        core.position = position
        core.zPosition = 26
        core.fillColor = UIColor(red: 0.53, green: 0.05, blue: 0.91, alpha: 0.88)
        core.strokeColor = UIColor(red: 0.91, green: 0.68, blue: 1.0, alpha: 0.96)
        core.lineWidth = 2.2
        core.glowWidth = 10
        addChild(core)
        core.run(.repeatForever(.sequence([
            .group([
                .scale(to: 1.18, duration: 0.16),
                .fadeAlpha(to: 0.68, duration: 0.16)
            ]),
            .group([
                .scale(to: 0.88, duration: 0.16),
                .fadeAlpha(to: 1.0, duration: 0.16)
            ])
        ])))
        return core
    }

    private func playHitFeedback() {
        hitFeedback.impactOccurred(intensity: 0.72)
        hitFeedback.prepare()
    }

    private func petalBurstPath(radius: CGFloat, petals: Int) -> CGPath {
        let path = UIBezierPath()
        let pointCount = petals * 2
        for index in 0..<pointCount {
            let angle = (CGFloat(index) / CGFloat(pointCount)) * (.pi * 2) - .pi / 2
            let scale: CGFloat = index.isMultiple(of: 2) ? 1.0 : 0.40
            let point = CGPoint(x: cos(angle) * radius * scale, y: sin(angle) * radius * scale)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.close()
        return path.cgPath
    }

    private func configureAmmoIndicator() {
        ammoIndicator.zPosition = 120
        ammoIndicator.isHidden = hideDebugHUD

        ammoBackdrop.fillColor = UIColor(white: 0.04, alpha: 0.76)
        ammoBackdrop.strokeColor = UIColor(red: 0.80, green: 0.61, blue: 0.25, alpha: 0.72)
        ammoBackdrop.lineWidth = 0.8
        ammoIndicator.addChild(ammoBackdrop)

        ammoPips = (0..<GameConfig.maxAmmo).map { index in
            let pip = SKShapeNode(circleOfRadius: 3.6)
            pip.position = CGPoint(x: CGFloat(index - 1) * 12, y: 0)
            pip.lineWidth = 0.8
            ammoIndicator.addChild(pip)
            return pip
        }
    }

    private func updateAmmoLabel() {
        guard !hideDebugHUD else { return }

        ammoIndicator.position = CGPoint(
            x: enemy.position.x,
            y: enemy.position.y + GameConfig.enemyCollisionRadius + 25
        )

        for (index, pip) in ammoPips.enumerated() {
            let isLoaded = index < enemy.ammo
            pip.fillColor = isLoaded
                ? UIColor(red: 0.98, green: 0.31, blue: 0.39, alpha: 1)
                : UIColor(white: 0.90, alpha: 0.15)
            pip.strokeColor = isLoaded
                ? UIColor(red: 1.00, green: 0.63, blue: 0.46, alpha: 0.95)
                : UIColor(white: 0.94, alpha: 0.38)
        }
    }

    private func publishSnapshot() {
        Task { @MainActor in
            sessionStore.update(
                GameSnapshot(
                    currentHP: player.currentHP,
                    maxHP: GameConfig.playerMaxHP,
                    survivalTime: survivalTime,
                    dodgedCount: dodgedCount,
                    hitCount: hitCount
                )
            )
        }
    }

    private func endGame() {
        guard !gameEnded else { return }
        gameEnded = true
        isPaused = true

        let result = GameResult(
            survivalTime: survivalTime,
            dodgedCount: dodgedCount,
            hitCount: hitCount,
            playerSpeedSetting: playerSpeedSetting
        )

        Task { @MainActor in
            onGameOver(result)
        }
    }

    private func endTouchesIfNeeded(_ touches: Set<UITouch>) {
        for touch in touches where joystick.containsTrackingTouch(touch) {
            joystick.endTracking(touch: touch)
            joystickTouch = nil
        }
    }
}
