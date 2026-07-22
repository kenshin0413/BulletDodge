import SpriteKit
import UIKit

final class GameScene: SKScene {
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
    private let joystick = VirtualJoystick()
    private let gameCamera = SKCameraNode()
    private let ammoLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let backgroundContainer = SKNode()
    private let explosionContainer = SKNode()

    private var bullets: [BulletNode] = []
    private var lastUpdateTime: TimeInterval = 0
    private var survivalTime: TimeInterval = 0
    private var dodgedCount = 0
    private var hitCount = 0
    private var gameEnded = false
    private var screenShakeTimeRemaining: TimeInterval = 0
    private var joystickTouch: UITouch?
    private var enemyReferencePoint: CGPoint = .zero
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

    init(seed: UUID, sessionStore: GameSessionStore, onGameOver: @escaping (GameResult) -> Void) {
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
        player.applyMovement(input: currentMovementInput, deltaTime: deltaTime, mapRect: playableRect)
        player.position = constrainedArenaPosition(player.position, collisionRadius: GameConfig.playerCollisionRadius)
        if autoWallTest {
            updateAutoWallRoute(deltaTime: deltaTime)
        }
        if GameConfig.enemyMovementEnabled && !autoWallTest && !autoAttackTest {
            updateEnemyReferencePoint(deltaTime: deltaTime)
            let enemyAnchor = preferredEnemyAnchorPosition()
            enemy.updateMovement(
                deltaTime: deltaTime,
                desiredAnchor: enemyAnchor,
                mapRect: playableRect
            )
            constrainEnemyToUpperLane()
        }
        enemy.updateReload(deltaTime: deltaTime)

        if GameConfig.enemyAttacksEnabled && !autoWallTest {
            switch enemy.updateAttack(deltaTime: deltaTime) {
            case .none:
                break
            case .beganThrow:
                scheduleAutoAttackCaptures()
            case .releaseProjectile:
                spawnBullet()
            }
        }

        updateBullets(deltaTime: deltaTime)
        updateCameraShake(deltaTime: deltaTime)
        updateCameraPosition()
        updateAmmoLabel()
        publishSnapshot()
        logAutoWallState(deltaTime: deltaTime)
        runAutoAttackCaptureIfNeeded()
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
        camera = gameCamera
        gameCamera.addChild(joystick)
        gameCamera.addChild(ammoLabel)

        mapNode.fillColor = .clear
        mapNode.strokeColor = .clear
        mapNode.lineWidth = 0
        mapNode.addChild(backgroundContainer)
        buildMapBackground()

        ammoLabel.fontSize = 12
        ammoLabel.horizontalAlignmentMode = .right
        ammoLabel.verticalAlignmentMode = .center
        ammoLabel.fontColor = .white
        ammoLabel.zPosition = 100
        ammoLabel.isHidden = hideDebugHUD
        joystick.isHidden = autoWallCapture

        resetState()
        layoutOverlayNodes()
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
        joystick.removeAllActions()

        player.reset()
        enemy.reset()
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

        ammoLabel.position = CGPoint(
            x: size.width / 2 - 16,
            y: size.height / 2 - 68
        )
    }

    private func buildMapBackground() {
        backgroundContainer.removeAllChildren()

        if let backgroundImage = UIImage(named: "arena_floor_v1") {
            let texture = SKTexture(image: backgroundImage)
            texture.filteringMode = .linear

            let floorSprite = SKSpriteNode(texture: texture, size: GameConfig.stageVisualSize)
            floorSprite.position = .zero
            floorSprite.zPosition = -20
            backgroundContainer.addChild(floorSprite)

            let topExtensionHeight = GameConfig.tileSize * 16.0
            let bottomExtensionHeight = GameConfig.tileSize * 8.0
            if let topSea = makeBackgroundSliceSprite(
                from: texture,
                imageSize: backgroundImage.size,
                cropRectTopLeft: CGRect(x: 0, y: 0, width: backgroundImage.size.width, height: 96),
                renderSize: CGSize(width: GameConfig.stageVisualSize.width, height: topExtensionHeight)
            ) {
                topSea.yScale = -1
                topSea.position = CGPoint(x: 0, y: GameConfig.stageVisualSize.height / 2 + topExtensionHeight / 2)
                topSea.zPosition = -21
                backgroundContainer.addChild(topSea)
            }

            if let bottomSea = makeBackgroundSliceSprite(
                from: texture,
                imageSize: backgroundImage.size,
                cropRectTopLeft: CGRect(x: 0, y: backgroundImage.size.height - 96, width: backgroundImage.size.width, height: 96),
                renderSize: CGSize(width: GameConfig.stageVisualSize.width, height: bottomExtensionHeight)
            ) {
                bottomSea.yScale = -1
                bottomSea.position = CGPoint(x: 0, y: -GameConfig.stageVisualSize.height / 2 - bottomExtensionHeight / 2)
                bottomSea.zPosition = -21
                backgroundContainer.addChild(bottomSea)
            }
        }

        let vignette = SKShapeNode(rectOf: GameConfig.stageVisualSize)
        vignette.fillColor = UIColor(red: 0.20, green: 0.05, blue: 0.17, alpha: 0.12)
        vignette.strokeColor = .clear
        vignette.zPosition = -3.5
        backgroundContainer.addChild(vignette)

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
        let visibleHeight = GameConfig.cameraVisibleHeight
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
               bullet.intersectsPlayer(
                   at: player.position,
                   containsPlayerPoint: player.containsHitPoint
               ) {
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

    private func detectHit(for bullet: BulletNode) -> Bool {
        if autoAttackTest {
            return false
        }
        if bullet.isTimedParent {
            return false
        }
        if !bullet.canDealContactDamage {
            return false
        }
        guard !bullet.hasDealtDamage else { return false }
        guard bullet.intersectsPlayer(
            at: player.position,
            containsPlayerPoint: player.containsHitPoint
        ) else { return false }

        bullet.registerHit()
        bullet.removeFromParent()
        hitCount += 1
        screenShakeTimeRemaining = GameConfig.shakeDuration
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let isDead = player.takeDamage(bullet.damage)
        if isDead {
            endGame()
        }

        return true
    }

    private func spawnBullet() {
        let targetPoint = makeThrowTargetPoint()
        let direction = CGVector(
            dx: targetPoint.x - enemy.position.x,
            dy: targetPoint.y - enemy.position.y
        ).normalized
        let rightHandOffset = CGVector(dx: direction.dy, dy: -direction.dx)
        let bullet = BulletNode.thornBall(direction: direction)
        bullet.position = CGPoint(
            x: enemy.position.x
                + direction.dx * (GameConfig.enemyVisualRadius + GameConfig.thornBallSpawnInset)
                + rightHandOffset.dx * (GameConfig.tileSize * 0.22),
            y: enemy.position.y
                + direction.dy * (GameConfig.enemyVisualRadius + GameConfig.thornBallSpawnInset)
                + rightHandOffset.dy * (GameConfig.tileSize * 0.22)
        )
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
        let visibleWidth = size.width * currentCameraScaleX
        let visibleHeight = size.height * currentCameraScaleY
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
        guard size.width > 0 else { return 1 }
        return GameConfig.cameraVisibleWidth / size.width
    }

    private var currentCameraScaleY: CGFloat {
        guard size.height > 0 else { return 1 }
        return GameConfig.cameraVisibleHeight / size.height
    }

    private func preferredEnemyAnchorPosition() -> CGPoint {
        let visibleWidth = size.width * currentCameraScaleX
        let visibleHeight = size.height * currentCameraScaleY
        let anchorPoint = CGPoint(
            x: enemyReferencePoint.x + visibleWidth * GameConfig.enemyAnchorHorizontalOffsetRatio,
            y: enemyReferencePoint.y + visibleHeight * GameConfig.enemyAnchorVerticalOffsetRatio
        )
        return constrainedArenaPosition(anchorPoint, collisionRadius: GameConfig.enemyCollisionRadius)
    }

    private func updateEnemyReferencePoint(deltaTime: TimeInterval) {
        let horizontalBlend = min(1, CGFloat(deltaTime) * GameConfig.enemyReferenceFollowRate)
        let verticalBlend = min(1, CGFloat(deltaTime) * (GameConfig.enemyReferenceFollowRate * 0.55))
        enemyReferencePoint = CGPoint(
            x: enemyReferencePoint.x + (player.position.x - enemyReferencePoint.x) * horizontalBlend,
            y: enemyReferencePoint.y + (player.position.y - enemyReferencePoint.y) * verticalBlend
        )
    }

    private func makeThrowTargetPoint() -> CGPoint {
        var refinedPoint = CGPoint(
            x: player.position.x + player.velocity.dx * GameConfig.thornBallTargetLeadFactor,
            y: player.position.y + player.velocity.dy * GameConfig.thornBallTargetLeadFactor
        )
        if GameConfig.debugProjectileTargetOffsetX != 0 || GameConfig.debugProjectileTargetOffsetY != 0 {
            refinedPoint.x += GameConfig.debugProjectileTargetOffsetX
            refinedPoint.y += GameConfig.debugProjectileTargetOffsetY
        }
        return refinedPoint.clamped(in: playableRect.insetBy(dx: 54, dy: 54))
    }

    private func handleExplosion(_ explosion: ExplosionSpec, from bullet: BulletNode) -> [BulletNode] {
        bullet.removeFromParent()
        applySplashDamage(at: explosion.position, radius: explosion.splashRadius, damage: explosion.splashDamage)
        spawnExplosionEffect(at: explosion.position)
        if GameConfig.debugProjectileLoggingEnabled {
            print("EXPLODE pos=(\(Int(explosion.position.x)),\(Int(explosion.position.y))) count=\(explosion.fragments.count)")
        }

        var fragments: [BulletNode] = []
        fragments.reserveCapacity(explosion.fragments.count)
        for (index, fragmentSpec) in explosion.fragments.enumerated() {
            let fragment = BulletNode.thornShard(
                direction: fragmentSpec.direction,
                angularVelocity: fragmentSpec.angularVelocity,
                keyframes: fragmentSpec.keyframes
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
        if autoAttackTest {
            return
        }
        let deltaX = (player.position.x - position.x) / (GameConfig.playerHitRadiusX + radius)
        let deltaY = (player.position.y - position.y) / (GameConfig.playerHitRadiusY + radius)
        guard deltaX * deltaX + deltaY * deltaY <= 1 else { return }

        hitCount += 1
        screenShakeTimeRemaining = GameConfig.shakeDuration
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let isDead = player.takeDamage(damage)
        if isDead {
            endGame()
        }
    }

    private func spawnExplosionEffect(at position: CGPoint) {
        let burstDiameter = GameConfig.explosionRadius * 2.15
        let burst = SKSpriteNode(
            texture: BulletNode.burstTexture,
            size: CGSize(width: burstDiameter, height: burstDiameter)
        )
        burst.position = position
        burst.zPosition = 26
        burst.alpha = 0
        burst.setScale(0.34)
        addChild(burst)

        let appear = SKAction.group([
            .scale(to: 0.92, duration: 0.016),
            .fadeAlpha(to: 0.92, duration: 0.016)
        ])
        let disappear = SKAction.group([
            .scale(to: 1.10, duration: 0.052),
            .fadeOut(withDuration: 0.052)
        ])
        burst.run(.sequence([appear, disappear, .removeFromParent()]))
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

    private func updateAmmoLabel() {
        guard !hideDebugHUD else { return }
        ammoLabel.text = "ENEMY AMMO \(enemy.ammo)/\(GameConfig.maxAmmo)"
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
            hitCount: hitCount
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
