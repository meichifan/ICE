//
//  IceScene.swift
//  ICE
//
//  场景：纯黑房间里的一张黑玻璃桌面 + 一块冰。
//
//  RealityKit 说明：
//   - 背景是纯色（不是环境贴图），所以画面只有冰块本身发光。
//   - 环境贴图只用来做 image-based lighting：给冰块提供反射和高光。
//   - 桌面上那层非常淡的倒影不是"反射"，而是一块沿 Y 翻转的冰块副本
//     （RealityKit 不做平面实时反射，这是业界通用的做法）。
//   - 没有可见的地面：桌面是"黑"的，靠倒影和冰块的位置暗示它存在。
//

import RealityKit
import UIKit

final class IceScene {

    static let cubeName = "iceCube"
    static let mirrorName = "iceMirror"
    static let dragPlaneName = "dragPlane"

    /// 冰块静止时中心的高度（米）——贴地
    static let cubeRestY: Float = IceCubeNode.size.y / 2

    private(set) var cube: ModelEntity!
    private(set) var mirror: Entity!
    private var camera = PerspectiveCamera()

    func build(in view: ARView) {
        // 背景：接近黑，但不是纯黑
        view.environment.background = .color(UIColor(red: 0.055, green: 0.06, blue: 0.07, alpha: 1.0))

        let root = AnchorEntity(world: .zero)
        view.scene.addAnchor(root)

        // 相机：带一点俯角的产品镜头（俯角大一点，纵深拖动的手感更线性）
        camera.camera.fieldOfViewInDegrees = 34
        camera.camera.near = 0.01
        camera.camera.far = 20
        camera.look(at: [0, IceScene.cubeRestY, 0],
                    from: [0, 0.34, 0.60],
                    upVector: [0, 1, 0],
                    relativeTo: nil)
        root.addChild(camera)

        // 环境光照：这个 SDK 的 EnvironmentResource 没有任何可用构造器，
        // 所以先用三点布光顶上（见下），IBL 等确认 API 后再补。

        // 主光：左上前方，制造冰的冷白高光
        let key = DirectionalLight()
        key.light.intensity = 4200
        key.light.color = .white
        key.look(at: [0, IceScene.cubeRestY, 0],
                 from: [-0.7, 1.2, 0.9],
                 upVector: [0, 1, 0], relativeTo: nil)
        root.addChild(key)

        // 补光：右侧偏冷，勾出另一条棱
        let fill = DirectionalLight()
        fill.light.intensity = 1500
        fill.light.color = UIColor(red: 0.84, green: 0.91, blue: 1.0, alpha: 1.0)
        fill.look(at: [0, IceScene.cubeRestY, 0],
                  from: [1.0, 0.5, 0.4],
                  upVector: [0, 1, 0], relativeTo: nil)
        root.addChild(fill)

        // 轮廓光：从后上方打过来，让冰的边缘亮起来（真冰最显眼的就是亮边）
        let rim = DirectionalLight()
        rim.light.intensity = 2600
        rim.light.color = UIColor(red: 0.90, green: 0.95, blue: 1.0, alpha: 1.0)
        rim.look(at: [0, IceScene.cubeRestY, 0],
                 from: [0.35, 0.9, -1.2],
                 upVector: [0, 1, 0], relativeTo: nil)
        root.addChild(rim)

        // 拖拽平面：不可见（只有碰撞体、没有模型），
        // 只用来把手指位置精确换算成桌面上的世界坐标
        let plane = Entity()
        plane.name = IceScene.dragPlaneName
        plane.components.set(CollisionComponent(shapes: [.generateBox(size: [8, 0.002, 8])]))
        root.addChild(plane)

        // 冰
        let cube = IceCubeNode.makeBody()
        cube.position = [0, IceScene.cubeRestY, 0]
        root.addChild(cube)
        self.cube = cube

        // 桌上那层很淡的倒影
        let mirror = IceCubeNode.makeReflection()
        mirror.position = [0, -IceScene.cubeRestY, 0]
        root.addChild(mirror)
        self.mirror = mirror

        iceLog("scene built: anchors=\(view.scene.anchors.count) rootChildren=\(root.children.count) envLighting=\(view.environment.lighting.resource != nil)")
        iceLog("cube pos=\(cube.position(relativeTo: nil)) visualBounds=\(cube.visualBounds(relativeTo: nil))")
        iceLog("cube material count=\(cube.model?.materials.count ?? -1)")
    }

    /// CI 诊断用
    func debugCamera() -> String {
        "pos=\(camera.position(relativeTo: nil)) orient=\(camera.orientation(relativeTo: nil))"
    }
}