//
//  IceCubeNode.swift
//  ICE
//
//  一块冰（真 3D）。
//
//  让"冰"成立的三件事（按重要性）：
//   1. 环境反射：IBL 提供的环境高光——冰的亮度几乎全部来自反射，
//      而不是自身的漫反射。所以 baseColor 压得很暗，透明区域接近"空"，
//      只有反射和雾气/裂纹的散射发亮。
//   2. 一张"冰体"贴图同时驱动三件事：
//        亮度 → 清的地方暗（透）、浊的地方白（霜）
//        透明度 → 清的地方透、浊的地方实
//        粗糙度 → 清的地方光滑（高光锐）、浊的地方霜面
//      这是真实冰块"清浊不均"的核心表现。
//   3. 不规则的几何：顶点扰动 + 棱边倒角 + 崩边，轮廓不是标准方盒。
//
//  再加一层桌面湿痕（接触环）和一块渐隐倒影，解决"悬浮感"。
//
//  所有贴图都用 Core Graphics 程序化生成，不依赖任何美术资源。
//

import RealityKit
import UIKit

// MARK: - 程序化贴图

enum IceTextures {

    /// 冰体贴图：暗底 + 白色霜雾团块 + 亮裂纹。
    /// 同一张图同时用作 baseColor / 透明度 / 粗糙度 三张贴图。
    static func iceBodyImage(side: CGFloat = 512) -> CGImage? {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)

            // 底部：干净的冰（暗、透）
            cg.setFillColor(UIColor(white: 0.05, alpha: 1).cgColor)
            cg.fill(rect)

            // 中间一团大的霜核：真实冰块最常见的形态
            drawBlob(cg, center: CGPoint(x: size.width * 0.5, y: size.height * 0.52),
                     radius: side * 0.30, alpha: 0.55)
            drawBlob(cg, center: CGPoint(x: size.width * 0.42, y: size.height * 0.45),
                     radius: side * 0.18, alpha: 0.45)

            // 大小不一的霜雾团块
            for _ in 0..<80 {
                let r = CGFloat.random(in: side * 0.03...side * 0.20)
                let x = CGFloat.random(in: 0...side)
                let y = CGFloat.random(in: 0...side)
                drawBlob(cg, center: CGPoint(x: x, y: y), radius: r,
                         alpha: CGFloat.random(in: 0.06...0.30))
            }

            // 裂纹：细而亮的线
            cg.setLineCap(.round)
            for _ in 0..<26 {
                let x0 = CGFloat.random(in: 0...side)
                let y0 = CGFloat.random(in: 0...side)
                let len = CGFloat.random(in: side * 0.05...side * 0.26)
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x0, y: y0))
                path.addLine(to: CGPoint(x: x0 + cos(angle) * len,
                                         y: y0 + sin(angle) * len))
                path.lineWidth = CGFloat.random(in: 0.6...1.8)
                UIColor(white: 1.0, alpha: CGFloat.random(in: 0.25...0.60)).setStroke()
                path.stroke()
            }

            // 气泡：零星亮点
            for _ in 0..<40 {
                let r = CGFloat.random(in: side * 0.004...side * 0.014)
                let x = CGFloat.random(in: 0...side)
                let y = CGFloat.random(in: 0...side)
                cg.setFillColor(UIColor(white: 1.0, alpha: CGFloat.random(in: 0.3...0.8)).cgColor)
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        return image.cgImage
    }

    private static func drawBlob(_ cg: CGContext,
                                 center: CGPoint,
                                 radius: CGFloat,
                                 alpha: CGFloat) {
        let colors = [
            UIColor(white: 1.0, alpha: alpha).cgColor,
            UIColor(white: 1.0, alpha: alpha * 0.45).cgColor,
            UIColor(white: 1.0, alpha: 0).cgColor
        ] as CFArray
        guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: colors, locations: [0, 0.5, 1]) else { return }
        cg.drawRadialGradient(grad,
                              startCenter: center, startRadius: 0,
                              endCenter: center, endRadius: radius,
                              options: [])
    }

    /// 桌面湿痕：一圈很淡的亮环（冰放在黑玻璃桌面上，接触处的水膜反光）
    static func wetRingImage(side: CGFloat = 256) -> CGImage? {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: side / 2, y: side / 2)
            let colors = [
                UIColor(white: 1.0, alpha: 0.0).cgColor,
                UIColor(white: 1.0, alpha: 0.55).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 0.72, 1]) else { return }
            cg.drawRadialGradient(grad,
                                  startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: side / 2,
                                  options: [])
        }
        return image.cgImage
    }

    /// CGImage -> TextureResource
    static func texture(from image: CGImage) -> TextureResource? {
        try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }
}

// MARK: - 不规则冰块网格

enum IceMesh {

    private static func hash(_ p: SIMD3<Float>) -> Float {
        let x = Int32(floor(p.x)), y = Int32(floor(p.y)), z = Int32(floor(p.z))
        var h = UInt32(bitPattern: x &* 374761393 &+ y &* 668265263 &+ z &* 1274126177)
        h = (h ^ (h >> 13)) &* 1274126177
        h = h ^ (h >> 16)
        return Float(h % 65536) / 65535.0
    }

    private static func noise(_ p: SIMD3<Float>) -> Float {
        let i = SIMD3<Float>(floor(p.x), floor(p.y), floor(p.z))
        let f = p - i
        let u = f * f * (3 - 2 * f)
        var result: Float = 0
        for dz in 0...1 {
            for dy in 0...1 {
                for dx in 0...1 {
                    let corner = i + SIMD3<Float>(Float(dx), Float(dy), Float(dz))
                    let c = hash(corner)
                    let wx = dx == 1 ? u.x : 1 - u.x
                    let wy = dy == 1 ? u.y : 1 - u.y
                    let wz = dz == 1 ? u.z : 1 - u.z
                    result += c * wx * wy * wz
                }
            }
        }
        return result
    }

    /// 不规则冰块：立方体表面做顶点扰动 + 棱边倒角 + 崩边 + 法线扰动。
    /// 失败返回 nil（调用方退回标准方盒，保证一定能跑）。
    static func makeIrregularBox(size: SIMD3<Float>, segments: Int = 16) -> MeshResource? {
        let half = size / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        let faces: [(axis: Int, sign: Float)] = [(0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1)]
        let n = segments
        let edgeWidth: Float = 0.18      // 棱边附近的倒角范围（占面宽比例）

        for face in faces {
            let base = UInt32(positions.count)
            let axisA = (face.axis + 1) % 3
            let axisB = (face.axis + 2) % 3

            for i in 0...n {
                for j in 0...n {
                    let fu = Float(i) / Float(n) * 2 - 1
                    let fv = Float(j) / Float(n) * 2 - 1

                    var p = SIMD3<Float>(repeating: 0)
                    p[face.axis] = half[face.axis] * face.sign
                    p[axisA] = half[axisA] * fu
                    p[axisB] = half[axisB] * fv

                    var normal = SIMD3<Float>(repeating: 0)
                    normal[face.axis] = face.sign

                    // 1) 棱边倒角：越靠近棱，表面越往里收
                    let edgeDistance = min(1 - abs(fu), 1 - abs(fv))
                    let chamferT = max(0, 1 - edgeDistance / edgeWidth)
                    let chamfer = chamferT * chamferT * 0.0055
                    p -= normal * chamfer

                    // 2) 大尺度起伏：整块冰的不规则
                    let big = (noise(p * 8.0) - 0.5) * 0.0060
                    // 3) 小尺度碎面：冻结表面的粗糙
                    let small = (noise(p * 34.0 + SIMD3(11, 5, 7)) - 0.5) * 0.0022
                    // 4) 崩边：棱附近随机缺口
                    let chip = chamferT * (noise(p * 20 + SIMD3(3, 17, 9)) - 0.5) * 0.0075
                    p += normal * (big + small + chip)

                    // 5) 法线扰动：让高光在表面碎开
                    let grad = SIMD3<Float>(
                        noise(p * 42 + SIMD3(1, 0, 0)) - 0.5,
                        noise(p * 42 + SIMD3(0, 1, 0)) - 0.5,
                        noise(p * 42 + SIMD3(0, 0, 1)) - 0.5
                    )
                    normal = simd_normalize(normal + grad * 0.70)

                    positions.append(p)
                    normals.append(normal)
                    uvs.append(SIMD2<Float>(Float(i) / Float(n), Float(j) / Float(n)))
                }
            }

            let flip = face.sign < 0
            for i in 0..<n {
                for j in 0..<n {
                    let i0 = base + UInt32(i * (n + 1) + j)
                    let i1 = i0 + 1
                    let i2 = i0 + UInt32(n + 1)
                    let i3 = i2 + 1
                    if flip {
                        indices += [i0, i3, i1, i0, i2, i3]
                    } else {
                        indices += [i0, i1, i3, i0, i3, i2]
                    }
                }
            }
        }

        var descriptor = MeshDescriptor(name: "irregularIce")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)

        return try? MeshResource.generate(from: [descriptor])
    }
}

// MARK: - 冰块

final class IceCubeNode {

    static let size: SIMD3<Float> = [0.09, 0.09, 0.09]

    /// 共享的冰体贴图（三用：颜色 / 透明度 / 粗糙度）
    private static let bodyTexture: TextureResource? = {
        guard let image = IceTextures.iceBodyImage() else { return nil }
        return IceTextures.texture(from: image)
    }()

    static func makeMesh() -> MeshResource {
        if let mesh = IceMesh.makeIrregularBox(size: size) { return mesh }
        return MeshResource.generateBox(size: size, cornerRadius: 0.002)
    }

    /// 冰体本体
    static func makeBody() -> ModelEntity {
        let entity = ModelEntity(mesh: makeMesh(), materials: [iceMaterial()])
        entity.name = IceScene.cubeName
        entity.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        return entity
    }

    /// 桌面湿痕：接触处一圈很淡的亮环
    static func makeContactRing() -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = UIColor(red: 0.82, green: 0.90, blue: 1.0, alpha: 1.0)
        material.roughness = .init(floatLiteral: 0.12)
        material.metallic = .init(floatLiteral: 0.0)
        if let image = IceTextures.wetRingImage(), let resource = IceTextures.texture(from: image) {
            material.blending = .transparent(opacity: .init(texture: MaterialParameters.Texture(resource)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: 0.25))
        }

        let entity = ModelEntity(
            mesh: .generatePlane(width: size.x * 1.35, depth: size.z * 1.35),
            materials: [material]
        )
        entity.name = IceScene.contactRingName
        return entity
    }

    /// 桌面上的倒影：分层，越往下越淡。容器整体沿 Y 翻转。
    static func makeReflection() -> Entity {
        let container = Entity()
        container.name = IceScene.mirrorName
        container.scale = [1, -1, 1]

        let layers = 6
        let layerHeight = size.y / Float(layers)
        let opacityTop: Float = 0.22

        for k in 0..<layers {
            // 容器本地 +y 对应世界方向的下方（因为容器被翻转）
            let localY = -size.y / 2 + layerHeight * (Float(k) + 0.5)
            let t = Float(k) / Float(layers - 1)
            let opacity = opacityTop * pow(1 - t, 1.7) + 0.008

            var material = iceMaterial()
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            material.baseColor.tint = UIColor(white: 0.62, alpha: 1.0)

            let slab = ModelEntity(
                mesh: .generateBox(size: [size.x * 0.88, layerHeight, size.z * 0.88]),
                materials: [material]
            )
            slab.position = [0, localY, 0]
            container.addChild(slab)
        }

        return container
    }

    // MARK: - 冰材质

    static func iceMaterial() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()

        // 冰本体几乎不漫反射：亮度全部来自环境反射和高光
        m.baseColor.tint = UIColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1.0)
        m.metallic = .init(floatLiteral: 0.0)
        m.specular = .init(floatLiteral: 1.0)

        // 表面水光：镜面反射
        m.clearcoat = .init(floatLiteral: 1.0)
        m.clearcoatRoughness = .init(floatLiteral: 0.02)

        // 诊断模式：实心不透明，用来判断"看不见"是材质问题还是几何/相机问题
        if ProcessInfo.processInfo.environment["ICE_SOLID"] == "1" {
            m.blending = .transparent(opacity: .init(floatLiteral: 0.95))
            m.roughness = .init(floatLiteral: 0.2)
            return m
        }

        if let body = bodyTexture {
            let map = MaterialParameters.Texture(body)
            m.baseColor = .init(texture: map)                        // 暗处透、亮处霜
            m.blending = .transparent(opacity: .init(texture: map))   // 暗处透、亮处实
            m.roughness = .init(texture: map)                         // 暗处光滑、亮处霜面
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: 0.35))
            m.roughness = .init(floatLiteral: 0.10)
        }

        return m
    }
}
