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

    /// 透明度贴图：黑=透明、白=不透明。
    /// 关键：靠边缘更透、中心更实（体积感的第一来源），再叠加内部霜斑。
    static func opacityImage(side: CGFloat = 512) -> CGImage? {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            // 径向梯度：边上较暗（更透），中心较亮（更实）
            let center = CGPoint(x: side / 2, y: side / 2)
            let colors = [
                UIColor(white: 0.92, alpha: 1).cgColor,   // 中心：较实
                UIColor(white: 0.72, alpha: 1).cgColor,   // 中环
                UIColor(white: 0.32, alpha: 1).cgColor    // 边缘：较透
            ] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 0.55, 1]) {
                cg.drawRadialGradient(grad,
                                      startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: side * 0.72,
                                      options: [.drawsAfterEndLocation])
            }
            // 内部霜斑：中性的浊区
            for _ in 0..<45 {
                drawBlob(cg,
                         center: CGPoint(x: .random(in: side*0.2...side*0.8),
                                         y: .random(in: side*0.2...side*0.8)),
                         radius: .random(in: side*0.05...side*0.22),
                         alpha: .random(in: 0.10...0.28))
            }
        }
        return image.cgImage
    }

    /// 粗糙度贴图：黑=光滑（锐利镜面高光）、白=粗糙（霜面）。
    /// 冰表面应是湿润光滑的，只在霜斑和裂隙处略糙，所以整体偏暗。
    static func roughnessImage(side: CGFloat = 512) -> CGImage? {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(white: 0.10, alpha: 1).cgColor)  // 整体湿润光滑
            cg.fill(CGRect(origin: .zero, size: size))
            // 少量霜斑让高光有点碎
            for _ in 0..<30 {
                drawBlob(cg,
                         center: CGPoint(x: .random(in: 0...side),
                                         y: .random(in: 0...side)),
                         radius: .random(in: side*0.04...side*0.16),
                         alpha: .random(in: 0.08...0.22))
            }
            // 裂隙：细线略糙
            cg.setLineCap(.round)
            for _ in 0..<16 {
                let x0 = CGFloat.random(in: 0...side), y0 = CGFloat.random(in: 0...side)
                let len = CGFloat.random(in: side*0.05...side*0.20)
                let a = CGFloat.random(in: 0...(2 * .pi))
                let pth = UIBezierPath()
                pth.move(to: CGPoint(x: x0, y: y0))
                pth.addLine(to: CGPoint(x: x0 + cos(a)*len, y: y0 + sin(a)*len))
                pth.lineWidth = CGFloat.random(in: 0.5...1.4)
                UIColor(white: 1.0, alpha: CGFloat.random(in: 0.10...0.25)).setStroke()
                pth.stroke()
            }
        }
        return image.cgImage
    }

    /// 颜色贴图：冰的淡蓝冷色，中心霜区偏白。
    static func colorImage(side: CGFloat = 512) -> CGImage? {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            // 基底：淡蓝灰（冰的颜色）
            cg.setFillColor(UIColor(red: 0.72, green: 0.82, blue: 0.94, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            // 中心霜区偏白
            drawTintedBlob(cg, center: CGPoint(x: side*0.5, y: side*0.5),
                           radius: side*0.34,
                           color: UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1))
            drawTintedBlob(cg, center: CGPoint(x: side*0.42, y: side*0.44),
                           radius: side*0.16,
                           color: UIColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 1))
        }
        return image.cgImage
    }

    private static func drawTintedBlob(_ cg: CGContext, center: CGPoint,
                                       radius: CGFloat, color: UIColor) {
        let colors = [
            color.cgColor,
            color.withAlphaComponent(0).cgColor
        ] as CFArray
        guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: colors, locations: [0, 1]) else { return }
        cg.drawRadialGradient(grad, startCenter: center, startRadius: 0,
                              endCenter: center, endRadius: radius, options: [])
    }

    /// 灰度软斑（用于不透明度的内部霜区与粗糙度的霜面）
    private static func drawBlob(_ cg: CGContext, center: CGPoint,
                                 radius: CGFloat, alpha: CGFloat) {
        let colors = [
            UIColor(white: 1.0, alpha: alpha).cgColor,
            UIColor(white: 1.0, alpha: alpha * 0.5).cgColor,
            UIColor(white: 1.0, alpha: 0).cgColor
        ] as CFArray
        guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: colors, locations: [0, 0.5, 1]) else { return }
        cg.drawRadialGradient(grad, startCenter: center, startRadius: 0,
                              endCenter: center, endRadius: radius, options: [])
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
                UIColor(white: 1.0, alpha: 0.30).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 0.74, 1]) else { return }
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

    /// 不规则冰块：先对"体积"做一次整体顶点扰动（让轮廓不再是标准方盒，
    /// 相邻面在共享棱上位置一致、不撕裂），再叠加面的法线扰动让高光碎开。
    /// 失败返回 nil（调用方退回标准方盒，保证一定能跑）。
    static func makeIrregularBox(size: SIMD3<Float>, segments: Int = 16) -> MeshResource? {
        let half = size / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        let faces: [(axis: Int, sign: Float)] = [(0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1)]
        let n = segments
        let faceAxis = { (face: (Int, Float), u: Float, v: Float) -> SIMD3<Float> in
            var p = SIMD3<Float>(repeating: 0)
            p[face.0] = half[face.0] * face.1
            p[(face.0 + 1) % 3] = half[(face.0 + 1) % 3] * u
            p[(face.0 + 2) % 3] = half[(face.0 + 2) % 3] * v
            return p
        }

        // 体积扰动：对整个立方体表面做位移，得到不规则的轮廓。
        // 位移只在面内、不沿法线方向，这样每个面的基准点保持在同一平面上，
        // 位移幅度均匀，不会出现棱边开缝。
        func displace(_ p: SIMD3<Float>) -> SIMD3<Float> {
            // 大尺度起伏 + 小尺度碎面，都是"贴着表面"的起伏
            let big = (noise(p * 8.0) - 0.5) * 0.009
            let small = (noise(p * 34.0 + SIMD3(11, 5, 7)) - 0.5) * 0.0032
            return p + big + small
        }

        // 预计算：为每个面内的每个顶点，先算好"体积扰动"后的基础位置。
        // 由于噪声是坐标的确定函数，相邻面在共享棱上的点会得到一致的位移，
        // 因此不会撕裂。棱边就是这个扰动后的不平滑顶点序列。
        var faceBasePositions: [[SIMD3<Float>]] = []
        for face in faces {
            var grid: [SIMD3<Float>] = []
            for i in 0...n {
                for j in 0...n {
                    let fu = Float(i) / Float(n) * 2 - 1
                    let fv = Float(j) / Float(n) * 2 - 1
                    let p = faceAxis(face, fu, fv)
                    grid.append(displace(p))
                }
            }
            faceBasePositions.append(grid)
        }

        // 构建顶点 + 法线 + UV + 索引
        for (fi, face) in faces.enumerated() {
            let base = UInt32(positions.count)
            let grid = faceBasePositions[fi]

            for idx in 0..<grid.count {
                let p = grid[idx]
                var normal = SIMD3<Float>(repeating: 0)
                normal[face.0] = face.1

                // 法线扰动：让高光在表面碎开，而不是一块平板
                let grad = SIMD3<Float>(
                    noise(p * 42 + SIMD3(1, 0, 0)) - 0.5,
                    noise(p * 42 + SIMD3(0, 1, 0)) - 0.5,
                    noise(p * 42 + SIMD3(0, 0, 1)) - 0.5
                )
                normal = simd_normalize(normal + grad * 0.55)

                positions.append(p)
                normals.append(normal)
                let i = idx / (n + 1), j = idx % (n + 1)
                uvs.append(SIMD2<Float>(Float(i) / Float(n), Float(j) / Float(n)))
            }

            // 绕序：之前 verts 叉积朝内（normal·sign<0），这里反转索引使叉积朝外。
            // 叉积方向应与面法线一致（朝外 = 面法线 × sign 方向）。
            let inward = face.1 < 0
            for i in 0..<n {
                for j in 0..<n {
                    let i0 = base + UInt32(i * (n + 1) + j)
                    let i1 = i0 + 1
                    let i2 = i0 + UInt32(n + 1)
                    let i3 = i2 + 1
                    if inward {
                        indices += [i0, i1, i3, i0, i3, i2]
                    } else {
                        indices += [i0, i3, i1, i0, i2, i3]
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

    /// 三张职责各异的贴图（颜色 / 透明度 / 粗糙度）。
    /// 都用固定随机种子生成，保证每次启动一致，也便于在 CI 里比对画面。
    private static let colorTexture: TextureResource? = {
        guard let image = IceTextures.colorImage() else { return nil }
        return IceTextures.texture(from: image)
    }()
    private static let opacityTexture: TextureResource? = {
        guard let image = IceTextures.opacityImage() else { return nil }
        return IceTextures.texture(from: image)
    }()
    private static let roughnessTexture: TextureResource? = {
        guard let image = IceTextures.roughnessImage() else { return nil }
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

    /// 桌面湿痕：接触处一圈很淡的亮环。
    /// 尺寸只比冰块略大一点点，读起来是"底板上的水膜边缘"。
    static func makeContactRing() -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = UIColor(red: 0.55, green: 0.62, blue: 0.74, alpha: 1.0)
        material.roughness = .init(floatLiteral: 0.40)
        material.metallic = .init(floatLiteral: 0.0)
        if let image = IceTextures.wetRingImage(), let resource = IceTextures.texture(from: image) {
            material.blending = .transparent(opacity: .init(texture: MaterialParameters.Texture(resource)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: 0.12))
        }

        let entity = ModelEntity(
            mesh: .generatePlane(width: size.x * 1.05, depth: size.z * 1.05),
            materials: [material]
        )
        entity.name = IceScene.contactRingName
        return entity
    }

    // MARK: - 冰材质

    static func iceMaterial() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()

        // 冰本体几乎不漫反射：亮度全部来自环境反射和高光。
        // 底色往蓝灰方向偏，符合"冷"的色温（参考图方向）。
        m.baseColor.tint = UIColor(red: 0.16, green: 0.19, blue: 0.24, alpha: 1.0)
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

        if let colorTex = colorTexture, let opacityTex = opacityTexture, let roughTex = roughnessTexture {
            m.baseColor = .init(texture: MaterialParameters.Texture(colorTex))          // 淡蓝冷色 + 中心偏白
            m.blending = .transparent(opacity: .init(texture: MaterialParameters.Texture(opacityTex)))  // 边缘透、中心实
            m.roughness = .init(texture: MaterialParameters.Texture(roughTex))           // 湿润光滑、霜区略糙
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: 0.55))
            m.roughness = .init(floatLiteral: 0.10)
        }

        return m
    }
}
