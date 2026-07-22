import SpriteKit

final class VirtualJoystick: SKNode {
    private let baseNode: SKShapeNode
    private let stickNode: SKShapeNode
    private let baseRadius: CGFloat = 64
    private let stickRadius: CGFloat = 28

    private(set) var inputVector: CGVector = .zero
    private var trackingTouchID: ObjectIdentifier?

    override init() {
        baseNode = SKShapeNode(circleOfRadius: baseRadius)
        stickNode = SKShapeNode(circleOfRadius: stickRadius)
        super.init()

        isUserInteractionEnabled = false

        baseNode.fillColor = UIColor.white.withAlphaComponent(0.18)
        baseNode.strokeColor = UIColor.white.withAlphaComponent(0.28)
        baseNode.lineWidth = 2

        stickNode.fillColor = UIColor.white.withAlphaComponent(0.42)
        stickNode.strokeColor = UIColor.clear

        addChild(baseNode)
        addChild(stickNode)
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    func beginTracking(touch: UITouch, at point: CGPoint) {
        trackingTouchID = ObjectIdentifier(touch)
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
        stickNode.run(.move(to: .zero, duration: 0.08))
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

    private func updateInput(with point: CGPoint) {
        let vector = CGVector(dx: point.x - position.x, dy: point.y - position.y)
        let distance = min(baseRadius, vector.length)
        let normalized = vector.normalized
        let limitedVector = normalized * distance
        let normalizedDistance = min(1, vector.length / baseRadius)
        let response = sqrt(normalizedDistance)

        inputVector = vector.length > 0 ? normalized * response : .zero
        stickNode.position = CGPoint(x: limitedVector.dx, y: limitedVector.dy)
    }
}
