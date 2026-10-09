import SpriteKit

/// Placeholder skeleton enemy. Origin is at the feet. Faces right by default.
final class SkeletonNode: SKNode {
    private let bone = SKColor(white: 0.93, alpha: 1)
    private let body = SKNode()

    override init() {
        super.init()
        let shadow = styled(SKShapeNode(ellipseOf: CGSize(width: 56, height: 12)),
                            SKColor(white: 0, alpha: 0.25), line: 0)
        addChild(shadow)
        addChild(body)
        body.position = CGPoint(x: 0, y: 28)

        func limb(_ w: CGFloat, _ h: CGFloat, x: CGFloat, y: CGFloat, z: CGFloat) -> SKShapeNode {
            let n = styled(SKShapeNode(rect: CGRect(x: -w / 2, y: -h, width: w, height: h), cornerRadius: w / 2),
                           bone, line: 3)
            n.position = CGPoint(x: x, y: y)
            n.zPosition = z
            body.addChild(n)
            return n
        }
        _ = limb(9, 28, x: -7, y: 0, z: -2)
        _ = limb(9, 28, x: 7, y: 0, z: -1)
        let armBack = limb(8, 26, x: -14, y: 44, z: -1)
        let armFront = limb(8, 26, x: 15, y: 44, z: 3)

        let ribs = styled(SKShapeNode(rect: CGRect(x: -16, y: 0, width: 32, height: 46), cornerRadius: 10),
                          bone, line: 3)
        let lines = CGMutablePath()
        for y: CGFloat in [14, 25, 36] {
            lines.move(to: CGPoint(x: -10, y: y))
            lines.addLine(to: CGPoint(x: 10, y: y))
        }
        let ribLines = SKShapeNode(path: lines)
        ribLines.strokeColor = ink
        ribLines.lineWidth = 3
        ribLines.lineCap = .round
        ribs.addChild(ribLines)
        body.addChild(ribs)

        let skull = styled(SKShapeNode(circleOfRadius: 16), bone)
        skull.position = CGPoint(x: 2, y: 64)
        skull.zPosition = 2
        for x: CGFloat in [-5, 7] {
            let eye = styled(SKShapeNode(ellipseOf: CGSize(width: 8, height: 10)), ink, line: 0)
            eye.position = CGPoint(x: x, y: 3)
            skull.addChild(eye)
        }
        let jaw = styled(SKShapeNode(rect: CGRect(x: -8, y: -14, width: 20, height: 7), cornerRadius: 3),
                         bone, line: 3)
        skull.addChild(jaw)
        body.addChild(skull)

        let blade = styled(SKShapeNode(rect: CGRect(x: -3, y: 0, width: 6, height: 42), cornerRadius: 2),
                           SKColor(red: 0.6, green: 0.55, blue: 0.5, alpha: 1), line: 3)
        blade.position = CGPoint(x: 0, y: -26)
        blade.zRotation = -1.14
        armFront.addChild(blade)
        armFront.zRotation = 0.5

        // Idle loop
        body.run(.repeatForever(.sequence([.moveTo(y: 31, duration: 0.6), .moveTo(y: 28, duration: 0.6)])))
        armFront.run(.repeatForever(.sequence([.rotate(toAngle: 0.6, duration: 0.6),
                                               .rotate(toAngle: 0.4, duration: 0.6)])))
        armBack.run(.repeatForever(.sequence([.rotate(toAngle: -0.05, duration: 0.6),
                                              .rotate(toAngle: 0.08, duration: 0.6)])))
    }
    required init?(coder: NSCoder) { fatalError() }

    func face(right: Bool) { xScale = (right ? 1 : -1) * abs(xScale) }
}
