//
//  IceInteraction.swift
//  ICE
//
//  第一阶段交互（3D 版）：
//   1. 点击：轻微下压缩放 + 极小的位置抖动 + 触觉反馈
//   2. 拖动：手指位置通过拖拽平面精确映射到桌面，冰块跟随（带一点迟滞）
//   3. 松手：按拖动速度产生惯性，逐渐减速，边缘软停止
//   4. 轻微旋转：随水平速度绕 Y 轴缓慢转动
//
//  不用物理引擎，全部手动数值积分——手感和参数完全可控。
//

import RealityKit
import UIKit
import simd

final class IceInteraction {

    private weak var view: IceARView?
    private weak var scene: IceScene?

    private let impact = UIImpactFeedbackGenerator(style: .light)

    // 拖拽状态
    private var isDragging = false
    private var touchStartPoint = CGPoint.zero
    private var touchStartTime: TimeInterval = 0
    private var movedDistance: CGFloat = 0
    private var lastTouchTime: TimeInterval = 0
    private var grabOffset = SIMD2<Float>.zero   // 抓取点与冰块中心的偏移（桌面平面）

    // 运动状态
    private var position = SIMD2<Float>.zero     // 桌面平面坐标 (x, z)
    private var velocity = SIMD2<Float>.zero     // m/s
    private var yaw: Float = 0
    private var yawRate: Float = 0

    // 视觉反馈（弹簧）
    private var scale: Float = 1
    private var scaleTarget: Float = 1
    private var scaleVelocity: Float = 0
    private var shake = SIMD2<Float>.zero
    private var shakeVelocity = SIMD2<Float>.zero

    // 手感参数
    private let followFactor: Float = 0.55       // 拖动跟随迟滞（越大越跟手）
    private let maxSpeed: Float = 3.0            // m/s
    private let stopSpeed: Float = 0.006
    private let dampingPerSecond: Float = 0.10   // 惯性每秒剩余比例
    private let rotationPerSpeed: Float = 0.55   // 速度 -> 角速度
    private let maxYawRate: Float = 1.0          // rad/s
    private let tapMaxDistance: CGFloat = 7
    private let tapMaxDuration: TimeInterval = 0.3

    // 可见桌面范围（用屏幕四角射线算出来），保证冰块永远滑不出画面
    private struct Edge {
        let z0: Float; let x0: Float
        let z1: Float; let x1: Float
        func x(at z: Float) -> Float {
            guard abs(z1 - z0) > 1e-6 else { return x0 }
            let k = (z - z0) / (z1 - z0)
            return x0 + (x1 - x0) * k
        }
    }
    private var leftEdge: Edge?
    private var rightEdge: Edge?
    private var zNear: Float = 0.10
    private var zFar: Float = -0.30

    init(view: IceARView, scene: IceScene) {
        self.view = view
        self.scene = scene
        self.position = SIMD2<Float>(scene.cube.position.x, scene.cube.position.z)
        impact.prepare()
    }

    // MARK: - 触摸

    func begin(at point: CGPoint, time: TimeInterval, in view: IceARView) {
        touchStartPoint = point
        touchStartTime = time
        movedDistance = 0

        // 必须按在冰上
        guard isTouchingIce(point, in: view),
              let world = worldPointOnTable(point, in: view) else { return }

        isDragging = true
        velocity = .zero
        yawRate = 0
        grabOffset = SIMD2<Float>(position.x - world.x, position.y - world.y)
        lastTouchTime = time

        // 按下：轻微下压
        scaleTarget = 0.95
        impact.impactOccurred()
    }

    func move(to point: CGPoint, time: TimeInterval, in view: IceARView) {
        guard isDragging else { return }
        movedDistance = hypot(point.x - touchStartPoint.x, point.y - touchStartPoint.y)

        guard let world = worldPointOnTable(point, in: view) else { return }

        let dt = Float(max(time - lastTouchTime, 1.0 / 240.0))
        lastTouchTime = time

        let target = SIMD2<Float>(world.x + grabOffset.x, world.y + grabOffset.y)
        var next = position + (target - position) * followFactor
        next = clampToTable(next)

        // 用实际位移计算速度，松手后的惯性和手感一致
        velocity = (next - position) / dt
        let speed = simd_length(velocity)
        if speed > maxSpeed { velocity *= maxSpeed / speed }

        position = next

        // 随水平速度轻微旋转
        yawRate = max(min(velocity.x * rotationPerSpeed, maxYawRate), -maxYawRate)
    }

    func end(at point: CGPoint, time: TimeInterval, in view: IceARView) {
        guard isDragging else { return }
        isDragging = false

        let duration = time - touchStartTime
        let isTap = movedDistance < tapMaxDistance && duration < tapMaxDuration

        let speed = simd_length(velocity)
        if speed > maxSpeed { velocity *= maxSpeed / speed }

        if isTap {
            // 点击：回弹（过冲一点）+ 轻微震动 + 触觉
            velocity = .zero
            yawRate = 0
            scaleTarget = 1.0
            scaleVelocity = 1.5
            let direction = SIMD2<Float>(Float.random(in: -1...1), Float.random(in: -1...1))
            shakeVelocity = simd_normalize(direction + SIMD2<Float>(0.001, 0.001)) * 0.02
            impact.impactOccurred()
        } else {
            scaleTarget = 1.0
        }
    }

    func cancel() {
        isDragging = false
        scaleTarget = 1.0
    }

    // MARK: - 每帧更新

    func update(dt: TimeInterval) {
        let dtf = Float(min(max(dt, 0), 1.0 / 20.0))
        guard dtf > 0 else { return }

        if !isDragging {
            // 惯性滑行
            let speed = simd_length(velocity)
            if speed > stopSpeed {
                velocity *= pow(dampingPerSecond, dtf)
                var next = position + velocity * dtf
                let clamped = clampToTable(next)
                if clamped.x != next.x { velocity.x = 0 }
                if clamped.y != next.y { velocity.y = 0 }
                next = clamped
                position = next
            } else {
                velocity = .zero
            }

            // 旋转衰减
            if abs(yawRate) > 0.002 {
                yawRate *= pow(0.12, dtf)
            } else {
                yawRate = 0
            }
        }

        yaw += yawRate * dtf

        // 缩放的弹簧（下压 / 回弹过冲）
        let stiffness: Float = 220
        let damping: Float = 18
        let scaleAccel = (scaleTarget - scale) * stiffness - scaleVelocity * damping
        scaleVelocity += scaleAccel * dtf
        scale += scaleVelocity * dtf
        if abs(scaleTarget - scale) < 0.0005 && abs(scaleVelocity) < 0.005 {
            scale = scaleTarget
            scaleVelocity = 0
        }

        // 位置抖动（点击的"视觉震动"）：弹簧回中
        let shakeAccel = -shake * 900 - shakeVelocity * 26
        shakeVelocity += shakeAccel * dtf
        shake += shakeVelocity * dtf
        if simd_length(shake) < 0.00002 && simd_length(shakeVelocity) < 0.0005 {
            shake = .zero
            shakeVelocity = .zero
        }

        applyTransform()
    }

    // MARK: - 应用到实体

    private func applyTransform() {
        guard let scene = scene, let cube = scene.cube, let mirror = scene.mirror else { return }

        let x = position.x + shake.x
        let z = position.y + shake.y

        cube.position = [x, IceScene.cubeRestY, z]
        cube.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        cube.scale = [scale, scale, scale]

        // 倒影：沿 Y 翻转，旋转取反
        mirror.position = [x, -IceScene.cubeRestY, z]
        mirror.orientation = simd_quatf(angle: -yaw, axis: [0, 1, 0])
        mirror.scale = [scale, -scale, scale]

        // 桌面湿痕跟着冰块走
        scene.contactRing.position = [x, 0.0006, z]
        scene.contactRing.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    // MARK: - 坐标换算与边界

    /// 手指在桌面上对应的世界坐标
    private func worldPointOnTable(_ point: CGPoint, in view: IceARView) -> SIMD2<Float>? {
        let hits = view.hitTest(point, query: .all, mask: .all)
        guard let hit = hits.first(where: { $0.entity.name == IceScene.dragPlaneName }) else { return nil }
        return SIMD2<Float>(hit.position.x, hit.position.z)
    }

    /// 手指是否按在冰上（冰体或其子节点）
    private func isTouchingIce(_ point: CGPoint, in view: IceARView) -> Bool {
        let hits = view.hitTest(point, query: .all, mask: .all)
        return hits.contains { hit in
            var entity: Entity? = hit.entity
            while let current = entity {
                if current.name == IceScene.cubeName { return true }
                entity = current.parent
            }
            return false
        }
    }

    private func clampToTable(_ p: SIMD2<Float>) -> SIMD2<Float> {
        // 纵深限制：太靠近相机 / 退到太远都会让冰块在画面里失控
        let z = min(max(p.y, zFar), zNear)

        // 横向限制：按当前纵深处可见的左/右边界，内缩冰块半径
        let half = IceCubeNode.size.x / 2 * 0.7
        let lo = (leftEdge?.x(at: z) ?? -0.20) + half
        let hi = (rightEdge?.x(at: z) ?? 0.20) - half
        let x = lo < hi ? min(max(p.x, lo), hi) : (lo + hi) / 2

        return SIMD2<Float>(x, z)
    }

    /// 用屏幕四角的射线在桌面上求交点，得到"可见桌面"的范围。
    /// 这样冰块永远不会被拖出画面，边缘会自然停住。
    func refreshVisibleTable(in view: IceARView) {
        let b = view.bounds
        guard b.width > 1, b.height > 1 else { return }

        func tablePoint(_ p: CGPoint) -> SIMD2<Float>? {
            let hits = view.hitTest(p, query: .all, mask: .all)
            guard let hit = hits.first(where: { $0.entity.name == IceScene.dragPlaneName }) else { return nil }
            return SIMD2<Float>(hit.position.x, hit.position.z)
        }

        guard let bottomLeft = tablePoint(CGPoint(x: 2, y: b.maxY - 2)),
              let topLeft = tablePoint(CGPoint(x: 2, y: 2)),
              let bottomRight = tablePoint(CGPoint(x: b.maxX - 2, y: b.maxY - 2)),
              let topRight = tablePoint(CGPoint(x: b.maxX - 2, y: 2)) else {
            iceLog("visible table: corner hit failed, keep defaults")
            return
        }

        leftEdge = Edge(z0: bottomLeft.y, x0: bottomLeft.x, z1: topLeft.y, x1: topLeft.x)
        rightEdge = Edge(z0: bottomRight.y, x0: bottomRight.x, z1: topRight.y, x1: topRight.x)

        // 最近可见处再留一点余量；最远处不要退到地平线附近（否则冰块会变得极小）
        zNear = max(bottomLeft.y, bottomRight.y) - 0.03
        zFar = -0.30

        iceLog("visible table z[\(zFar)...\(zNear)] "
               + "leftX@home=\(leftEdge?.x(at: 0) ?? 0) rightX@home=\(rightEdge?.x(at: 0) ?? 0)")
    }
}
