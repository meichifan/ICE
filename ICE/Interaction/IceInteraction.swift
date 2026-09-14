//
//  IceInteraction.swift
//  ICE
//
//  第一阶段交互逻辑：
//  - 点击：轻微缩放回弹 + 轻微震动位移 + UIImpactFeedback
//  - 拖动：冰块跟随手指，松手后带惯性滑行并逐渐减速
//  - 轻微旋转：拖动时给一点随机的缓慢旋转，像冰块在玻璃上蹭着转
//
//  不用真实刚体物理，全部是手动数值积分，优先手感稳定。
//

import SpriteKit
import UIKit

final class IceInteraction {

    private weak var ice: IceCubeNode?

    // 触觉反馈
    private let impactLight = UIImpactFeedbackGenerator(style: .light)

    // 拖动状态
    private var isDragging = false
    private var dragOffset: CGPoint = .zero

    // 惯性（点/秒）
    private var velocity: CGPoint = .zero
    // 最近几帧的触摸速度采样，用于松手时估算惯性
    private var lastTouchPosition: CGPoint = .zero
    private var lastTouchTime: TimeInterval = 0

    // 旋转（弧度/秒）
    private var angularVelocity: CGFloat = 0

    // 阻尼：速度每秒衰减到的比例（越小停得越快）
    private let linearDampingPerSecond: CGFloat = 0.90
    private let angularDampingPerSecond: CGFloat = 0.92

    init(ice: IceCubeNode) {
        self.ice = ice
        impactLight.prepare()
    }

    // MARK: - 触摸事件（由 IceScene 转发）

    func touchBegan(at point: CGPoint, time: TimeInterval) -> Bool {
        guard let ice = ice else { return false }

        let touched = ice.bodySprite.contains(point)
        guard touched else { return false }

        // 停止所有进行中的动画
        ice.removeAllActions()
        velocity = .zero
        angularVelocity = 0

        // 判断是拖动开始（按住即视为可拖）
        isDragging = true
        dragOffset = CGPoint(x: ice.position.x - point.x,
                             y: ice.position.y - point.y)
        lastTouchPosition = point
        lastTouchTime = time

        // 点击反馈：轻微下压
        let press = SKAction.scale(to: 0.96, duration: 0.09)
        press.timingMode = .easeOut
        ice.run(press)
        impactLight.impactOccurred()

        return true
    }

    func touchMoved(to point: CGPoint, time: TimeInterval) {
        guard isDragging, let ice = ice else { return }

        // 采样触摸速度
        let dt = max(time - lastTouchTime, 1.0 / 240)
        let sampledVelocity = CGPoint(x: (point.x - lastTouchPosition.x) / dt,
                                      y: (point.y - lastTouchPosition.y) / dt)
        velocity = sampledVelocity
        lastTouchPosition = point
        lastTouchTime = time

        // 冰块跟随手指（保留按下时的偏移）
        let target = CGPoint(x: point.x + dragOffset.x,
                             y: point.y + dragOffset.y)
        // 轻微平滑，避免一帧跳变
        let smoothed = CGPoint(x: ice.position.x + (target.x - ice.position.x) * 0.6,
                               y: ice.position.y + (target.y - ice.position.y) * 0.6)
        ice.position = clampedToScene(smoothed)

        // 拖动时给一个与水平速度相关的小角速度
        angularVelocity = (sampledVelocity.x / 1400) * .pi / 6
        angularVelocity = max(min(angularVelocity, 0.35), -0.35)
    }

    func touchEnded() {
        guard isDragging, let ice = ice else { return }
        isDragging = false

        // 回弹：先过冲到 1.02 再回到 1.0，模拟弹簧手感
        let overshoot = SKAction.scale(to: 1.02, duration: 0.12)
        overshoot.timingMode = .easeOut
        let settle = SKAction.scale(to: 1.0, duration: 0.22)
        settle.timingMode = .easeInEaseOut
        ice.run(.sequence([overshoot, settle]))

        // 轻微视觉震动（两个小位移）
        let jiggle = SKAction.sequence([
            .moveBy(x: 1.5, y: -1, duration: 0.04),
            .moveBy(x: -1.5, y: 1, duration: 0.05)
        ])
        ice.run(jiggle)

        // 限制最大惯性，防止甩飞
        let maxSpeed: CGFloat = 1400
        let speed = hypot(velocity.x, velocity.y)
        if speed > maxSpeed {
            let k = maxSpeed / speed
            velocity = CGPoint(x: velocity.x * k, y: velocity.y * k)
        }
    }

    func touchCancelled() {
        isDragging = false
        velocity = .zero
        angularVelocity = 0
        ice?.run(.scale(to: 1.0, duration: 0.2))
    }

    // MARK: - 每帧更新（由 IceScene.update 调用）

    func update(deltaTime dt: TimeInterval) {
        guard let ice = ice, dt > 0, dt < 1 else { return }
        let dtF = CGFloat(dt)

        if !isDragging {
            // 惯性滑行
            if hypot(velocity.x, velocity.y) > 0.5 {
                let damp = pow(linearDampingPerSecond, dtF)
                velocity = CGPoint(x: velocity.x * damp, y: velocity.y * damp)
                let newPos = CGPoint(x: ice.position.x + velocity.x * dtF,
                                     y: ice.position.y + velocity.y * dtF)
                ice.position = clampedToScene(newPos)

                // 滑到边缘就停（不弹跳）
                if ice.position != newPos { velocity = .zero }
            } else {
                velocity = .zero
            }

            // 缓慢旋转衰减
            if abs(angularVelocity) > 0.001 {
                angularVelocity *= pow(angularDampingPerSecond, dtF)
                ice.zRotation += angularVelocity * dtF
            } else {
                angularVelocity = 0
            }
        }
    }

    // MARK: - 边界

    private func clampedToScene(_ p: CGPoint) -> CGPoint {
        guard let scene = ice?.scene else { return p }
        let half = IceCubeNode.edge / 2
        let inset: CGFloat = 8
        let minX = half + inset
        let maxX = scene.size.width - half - inset
        let minY = half + inset
        let maxY = scene.size.height - half - inset
        return CGPoint(x: max(minX, min(maxX, p.x)),
                       y: max(minY, min(maxY, p.y)))
    }
}
