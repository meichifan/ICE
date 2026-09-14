//
//  IceSceneView.swift
//  ICE
//
//  SwiftUI 与 RealityKit 之间的桥。
//
//  用 ARView 的 .nonAR 模式跑纯 RealityKit 渲染：不用摄像头、不需要 AR 权限，
//  兼容范围也比 RealityView 更宽（iOS 13+）。
//
//  另外内置一个"自动拖动"脚本（只在设置了 ICE_AUTODRAG=1 时生效），
//  供 CI 在模拟器里截图验收交互效果，对正常使用没有任何影响。
//

import SwiftUI
import RealityKit
import Combine

struct IceSceneView: UIViewRepresentable {

    func makeUIView(context: Context) -> IceARView {
        IceARView(frame: .zero)
    }

    func updateUIView(_ uiView: IceARView, context: Context) {
        // 场景是自足的，不需要根据 SwiftUI 状态更新
    }
}

final class IceARView: ARView {

    private let iceScene = IceScene()
    private var interaction: IceInteraction?
    private var updateSubscription: Cancellable?

    // CI 验收用的脚本化拖动
    private var scriptTimer: Timer?
    private var scriptPhaseStart = CACurrentMediaTime()
    private var scriptDragging = false

    required init(frame: CGRect) {
        super.init(frame: frame)

        // 纯虚拟场景：不用摄像头
        cameraMode = .nonAR

        // ARView 自带的交互手势会抢触摸，全部关掉
        gestureRecognizers?.forEach { $0.isEnabled = false }

        iceScene.build(in: self)
        interaction = IceInteraction(view: self, scene: iceScene)

        // 每帧驱动惯性 / 弹簧
        updateSubscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.interaction?.update(dt: event.deltaTime)
        }

        startScriptedDragIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 触摸转发

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        interaction?.begin(at: touch.location(in: self), time: touch.timestamp, in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        interaction?.move(to: touch.location(in: self), time: touch.timestamp, in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        interaction?.end(at: touch.location(in: self), time: touch.timestamp, in: self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        interaction?.cancel()
    }

    // MARK: - CI 验收脚本

    private func startScriptedDragIfNeeded() {
        guard ProcessInfo.processInfo.environment["ICE_AUTODRAG"] == "1" else { return }
        scriptPhaseStart = CACurrentMediaTime()
        scriptTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickScriptedDrag()
        }
    }

    private func tickScriptedDrag() {
        guard let interaction else { return }
        let now = CACurrentMediaTime()
        let phase = (now - scriptPhaseStart).truncatingRemainder(dividingBy: 4.0)

        let start = CGPoint(x: bounds.midX - 24, y: bounds.midY + 34)
        let end = CGPoint(x: bounds.midX + 150, y: bounds.midY - 120)

        if phase < 1.0 {
            if !scriptDragging {
                scriptDragging = true
                interaction.begin(at: start, time: now, in: self)
            } else {
                let k = CGFloat(phase)
                let point = CGPoint(x: start.x + (end.x - start.x) * k,
                                    y: start.y + (end.y - start.y) * k)
                interaction.move(to: point, time: now, in: self)
            }
        } else if scriptDragging {
            scriptDragging = false
            interaction.end(at: end, time: now, in: self)
        }
    }
}
