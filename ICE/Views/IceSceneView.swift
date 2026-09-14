//
//  IceSceneView.swift
//  ICE
//
//  SwiftUI 与 RealityKit 之间的桥。
//
//  用 ARView 的 .nonAR 模式跑纯 RealityKit 渲染：不用摄像头、不需要 AR 权限，
//  兼容范围也比 RealityView 更宽（iOS 13+）。
//
//  两个只在 CI 里开启的开关（环境变量），对正常使用没有任何影响：
//   ICE_AUTODRAG=1  自动反复做一次拖动，方便截到"拖动中/惯性中"的画面
//   ICE_DIAG=1      输出场景诊断信息（几何体位置、点击命中结果）
//

import SwiftUI
import RealityKit
import Combine

/// 诊断日志走 stderr（stdout 被管道缓冲会丢），CI 里用 simctl --console 抓取
func iceLog(_ message: String) {
    FileHandle.standardError.write(Data(("[ICE] " + message + "\n").utf8))
}

struct IceSceneView: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> IceViewController {
        IceViewController()
    }

    func updateUIViewController(_ viewController: IceViewController, context: Context) {
        // 场景是自足的，不需要根据 SwiftUI 状态更新
    }
}

/// 用 UIViewController 承载，才能可靠地隐藏状态栏（SwiftUI 的 statusBarHidden 在这里不生效）
final class IceViewController: UIViewController {

    private let arView = IceARView(frame: .zero)

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func loadView() {
        let container = UIView()
        container.backgroundColor = UIColor(red: 0.055, green: 0.06, blue: 0.07, alpha: 1.0)
        arView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(arView)
        NSLayoutConstraint.activate([
            arView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            arView.topAnchor.constraint(equalTo: container.topAnchor),
            arView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsStatusBarAppearanceUpdate()
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
    private var lastHeartbeat: TimeInterval = 0

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
        scheduleDiagnostics()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iceLog("layoutSubviews bounds=\(bounds)")
        interaction?.refreshVisibleTable(in: self)
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

    // MARK: - CI 诊断

    private func scheduleDiagnostics() {
        guard ProcessInfo.processInfo.environment["ICE_DIAG"] == "1" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self else { return }
            let center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            let hits = self.hitTest(center, query: .all, mask: .all)
            iceLog("diag bounds=\(self.bounds)")
            iceLog("diag hits at center count=\(hits.count) names=\(hits.map { $0.entity.name })")
            if let cube = self.iceScene.cube {
                iceLog("diag cube pos=\(cube.position(relativeTo: nil)) scale=\(cube.scale)")
                iceLog("diag cube visualBounds=\(cube.visualBounds(relativeTo: nil))")
            }
            iceLog("diag camera=\(self.iceScene.debugCamera())")
            iceLog("diag anchors=\(self.scene.anchors.count)")
        }
    }

    // MARK: - CI 验收脚本

    private func startScriptedDragIfNeeded() {
        guard ProcessInfo.processInfo.environment["ICE_AUTODRAG"] == "1" else { return }
        // 前 5 秒不动，方便截到"静止的冰块"
        scriptPhaseStart = CACurrentMediaTime() + 5
        scriptTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickScriptedDrag()
        }
    }

    private func tickScriptedDrag() {
        guard let interaction else { return }
        let now = CACurrentMediaTime()

        // 心跳：确认主线程还在跑、并记录冰块位置
        if now - lastHeartbeat > 1.0 {
            lastHeartbeat = now
            let p = iceScene.cube?.position(relativeTo: nil) ?? .zero
            iceLog("heartbeat t=\(Int((now - scriptPhaseStart).rounded())) drag=\(scriptDragging) cube=(\(String(format: "%.3f", p.x)), \(String(format: "%.3f", p.z)))")
        }

        guard now >= scriptPhaseStart else { return }
        let phase = (now - scriptPhaseStart).truncatingRemainder(dividingBy: 4.0)

        let start = CGPoint(x: bounds.midX - 24, y: bounds.midY + 34)
        let end = CGPoint(x: bounds.midX + 100, y: bounds.midY - 70)

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
