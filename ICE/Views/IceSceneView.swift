//
//  IceSceneView.swift
//  ICE
//
//  SwiftUI 与 RealityKit 之间的桥。
//
//  用 ARView 的 .nonAR 模式跑纯 RealityKit 渲染：不用摄像头、不需要 AR 权限，
//  兼容范围也比 RealityView 更宽（iOS 13+）。
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 触摸转发

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        interaction?.touchesBegan(touches, in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        interaction?.touchesMoved(touches, in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        interaction?.touchesEnded(touches, in: self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        interaction?.touchesCancelled(touches, in: self)
    }
}
