//
//  IceScene.swift
//  ICE
//
//  SpriteKit 场景：深灰黑背景 + 一块冰。
//  只负责创建对象、转发触摸事件、驱动每帧更新。
//  交互细节全部在 IceInteraction 里。
//

import SpriteKit

final class IceScene: SKScene {

    private var ice: IceCubeNode!
    private var interaction: IceInteraction!
    private var lastUpdateTime: TimeInterval = 0

    override func didMove(to view: SKView) {
        // 深灰黑背景，接近黑但不纯黑
        backgroundColor = UIColor(red: 0.055, green: 0.06, blue: 0.07, alpha: 1.0)

        ice = IceCubeNode()
        ice.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(ice)

        interaction = IceInteraction(ice: ice)
    }

    // MARK: - 触摸转发

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let time = touch.timestamp
        _ = interaction.touchBegan(at: point, time: time)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        interaction.touchMoved(to: touch.location(in: self), time: touch.timestamp)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        interaction.touchEnded()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        interaction.touchCancelled()
    }

    // MARK: - 主循环

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        interaction.update(deltaTime: dt)
    }
}
