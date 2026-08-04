import SpriteKit

final class VirtualJoystick: SKNode {
    private let baseNode: SKShapeNode
    private let stickNode: SKShapeNode
    private let baseRadius: CGFloat = 64
    private let stickRadius: CGFloat = 28
    private let mode: JoystickMode

    private(set) var inputVector: CGVector = .zero
    private var trackingTouchID: ObjectIdentifier?

    init(mode: JoystickMode) {
        self.mode = mode
        baseNode = SKShapeNode(circleOfRadius: baseRadius)
        stickNode = SKShapeNode(circleOfRadius: stickRadius)
        super.init()

        isUserInteractionEnabled = false
        baseNode.lineWidth = 2
        stickNode.strokeColor = UIColor.clear

        addChild(baseNode)
        addChild(stickNode)
        configureAppearance()
        alpha = mode == .floating ? 0 : 1
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func beginTracking(touch: UITouch, at point: CGPoint) {
        removeAllActions()
        trackingTouchID = ObjectIdentifier(touch)

        if mode == .floating {
            position = point
            stickNode.position = .zero
            alpha = 0
            run(.fadeIn(withDuration: 0.06))
        }

        updateInput(with: point)
    }

    func updateTracking(touch: UITouch, at point: CGPoint) {
        guard trackingTouchID == ObjectIdentifier(touch) else { return }
        updateInput(with: point)
    }

    func endTracking(touch: UITouch) {
        guard trackingTouchID == ObjectIdentifier(touch) else { return }
        trackingTouchID = nil
        inputVector = .zero
        stickNode.removeAllActions()

        if mode == .floating {
            let settle = SKAction.move(to: .zero, duration: 0.06)
            settle.timingMode = .easeOut
            stickNode.run(settle)
            run(.sequence([
                .wait(forDuration: 0.025),
                .fadeOut(withDuration: 0.11)
            ]))
        } else {
            let settle = SKAction.move(to: .zero, duration: 0.08)
            settle.timingMode = .easeOut
            stickNode.run(settle)
        }
    }

    func containsTrackingTouch(_ touch: UITouch) -> Bool {
        trackingTouchID == ObjectIdentifier(touch)
    }

    func activationFrame(in sceneSize: CGSize) -> CGRect {
        CGRect(
            x: -sceneSize.width / 2,
            y: -sceneSize.height / 2,
            width: min(sceneSize.width * 0.4, 340),
            height: sceneSize.height
        )
    }

    func reset() {
        trackingTouchID = nil
        inputVector = .zero
        removeAllActions()
        stickNode.removeAllActions()
        stickNode.position = .zero
        alpha = mode == .floating ? 0 : 1
    }

#if DEBUG
    func showFloatingPreview(at origin: CGPoint, draggedTo point: CGPoint) {
        guard mode == .floating else { return }
        removeAllActions()
        position = origin
        alpha = 1
        updateInput(with: point)
    }
#endif

    private func updateInput(with point: CGPoint) {
        var vector = CGVector(dx: point.x - position.x, dy: point.y - position.y)

        // Brawl-style floating control: the base starts where the finger lands.
        // Once the finger passes the control radius, the base catches up just
        // enough to keep the knob on its rim instead of leaving it behind.
        if mode == .floating, vector.length > baseRadius {
            let direction = vector.normalized
            let overflow = vector.length - baseRadius
            position = CGPoint(
                x: position.x + direction.dx * overflow,
                y: position.y + direction.dy * overflow
            )
            vector = CGVector(dx: point.x - position.x, dy: point.y - position.y)
        }

        let distance = min(baseRadius, vector.length)
        let normalized = vector.normalized
        let limitedVector = normalized * distance
        let normalizedDistance = min(1, vector.length / baseRadius)
        let response = sqrt(normalizedDistance)

        inputVector = vector.length > 0 ? normalized * response : .zero
        stickNode.position = CGPoint(x: limitedVector.dx, y: limitedVector.dy)
    }

    private func configureAppearance() {
        if mode == .floating {
            stickNode.setScale(0.90)
        }

        baseNode.fillColor = UIColor(
            red: 0.02,
            green: 0.43,
            blue: 0.58,
            alpha: 0.16
        )
        baseNode.strokeColor = UIColor(
            red: 0.08,
            green: 0.67,
            blue: 0.74,
            alpha: 0.34
        )
        stickNode.fillColor = UIColor(
            red: 0.01,
            green: 0.25,
            blue: 0.36,
            alpha: 0.64
        )
        stickNode.strokeColor = UIColor(
            red: 0.08,
            green: 0.67,
            blue: 0.74,
            alpha: 0.24
        )
        stickNode.lineWidth = 2
    }
}
