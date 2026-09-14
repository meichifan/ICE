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

    private struct SeededRandom {
        var state: UInt32 = 0x1CE5EED
        mutating func next() -> CGFloat {
            state = 1664525 &* state &+ 1013904223
            return CGFloat(state) / CGFloat(UInt32.max)
        }
        mutating func range(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            lower + (upper - lower) * next()
        }
    }

    /// 透明度贴图：边缘更有厚度，中心只保留低对比的冰体密度。
    static func opacityImage(side: CGFloat = 512) -> CGImage? {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            // 低对比体积密度：避免整块统一 alpha，也避免玻璃式透明渐变。
            let center = CGPoint(x: side / 2, y: side / 2)
            let colors = [
                UIColor(white: 0.25, alpha: 1).cgColor,
                UIColor(white: 0.30, alpha: 1).cgColor,
                UIColor(white: 0.48, alpha: 1).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 0.55, 1]) {
                cg.drawRadialGradient(grad,
                                      startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: side * 0.72,
                                      options: [.drawsAfterEndLocation])
            }
            var random = SeededRandom()
            // 局部浑浊：只改变密度，不画白色光斑。
            for _ in 0..<12 {
                drawBlob(cg,
                         center: CGPoint(x: random.range(side * 0.18, side * 0.82),
                                         y: random.range(side * 0.16, side * 0.84)),
                         radius: random.range(side * 0.035, side * 0.11),
                         alpha: random.range(0.035, 0.09))
            }
            // 微气泡：很小、低透明、不同深度的密度变化，不做成 UI 圆点。
            for _ in 0..<28 {
                let r = random.range(side * 0.004, side * 0.012)
                drawBlob(cg,
                         center: CGPoint(x: random.range(side * 0.12, side * 0.88),
                                         y: random.range(side * 0.10, side * 0.90)),
                         radius: r,
                         alpha: random.range(0.035, 0.085))
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
            cg.setFillColor(UIColor(white: 0.30, alpha: 1).cgColor)  // 冰面，不是镜面玻璃
            cg.fill(CGRect(origin: .zero, size: size))
            var random = SeededRandom()
            // 少量冰层让反射出现不规则断续，而不是一整块高光。
            for _ in 0..<10 {
                drawBlob(cg,
                         center: CGPoint(x: random.range(side * 0.08, side * 0.92),
                                         y: random.range(side * 0.08, side * 0.92)),
                         radius: random.range(side * 0.025, side * 0.10),
                         alpha: random.range(0.06, 0.14))
            }
            // 极少量微裂隙：只在近看时打碎高光。
            cg.setLineCap(.round)
            for _ in 0..<7 {
                let x0 = random.range(side * 0.10, side * 0.90)
                let y0 = random.range(side * 0.10, side * 0.90)
                let len = random.range(side * 0.025, side * 0.09)
                let a = random.range(0, 2 * .pi)
                let pth = UIBezierPath()
                pth.move(to: CGPoint(x: x0, y: y0))
                pth.addLine(to: CGPoint(x: x0 + cos(a) * len, y: y0 + sin(a) * len))
                pth.lineWidth = random.range(0.45, 1.0)
                UIColor(white: 1.0, alpha: random.range(0.08, 0.16)).setStroke()
                pth.stroke()
            }
        }
        return image.cgImage
    }

    /// 颜色贴图：接近透明冷白；不把冰染成蓝色，也不叠加大面积白斑。
    static func colorImage(side: CGFloat = 512) -> CGImage? {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 0.78, green: 0.84, blue: 0.90, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
        }
        return image.cgImage
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

    /// 桌面接触阴影：暗而柔，不使用白色椭圆或人工发光。
    static func wetRingImage(side: CGFloat = 256) -> CGImage? {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: side / 2, y: side / 2)
            let colors = [
                UIColor(white: 0.0, alpha: 0.20).cgColor,
                UIColor(white: 0.0, alpha: 0.10).cgColor,
                UIColor(white: 0.0, alpha: 0.0).cgColor
            ] as CFArray
            guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 0.62, 1]) else { return }
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
            // 非常轻的弯曲与崩边：仍然是冰块，不是石头或几何方盒。
            let broad = (noise(p * 7.0 + SIMD3(3, 9, 2)) - 0.5) * 0.0032
            let fine = (noise(p * 28.0 + SIMD3(11, 5, 7)) - 0.5) * 0.0012
            var q = p
            q.x += broad * (1 - abs(p.x / half.x) * 0.35)
            q.z += fine * (1 - abs(p.z / half.z) * 0.35)
            // 顶部和底部稍微不平，四角扰动很小且彼此不同。
            q.y += (abs(p.y) > half.y * 0.98 ? broad * 0.55 : 0)
            return q
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

    static let size: SIMD3<Float> = [0.073, 0.073, 0.073]

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

    /// 桌面接触阴影：只负责让冰块贴地，不参与冰体高光。
    static func makeContactRing() -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor.tint = UIColor(white: 0.02, alpha: 1.0)
        material.roughness = .init(floatLiteral: 0.92)
        material.metallic = .init(floatLiteral: 0.0)
        if let image = IceTextures.wetRingImage(), let resource = IceTextures.texture(from: image) {
            material.blending = .transparent(opacity: .init(texture: MaterialParameters.Texture(resource)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: 0.12))
        }

        let entity = ModelEntity(
            mesh: .generatePlane(width: size.x * 0.92, depth: size.z * 0.92),
            materials: [material]
        )
        entity.name = IceScene.contactRingName
        return entity
    }

    // MARK: - 冰材质

    static func iceMaterial() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()

        // 冰不自发光：亮度来自环境反射，底色只保留冷白灰。
        m.baseColor.tint = UIColor(red: 0.82, green: 0.87, blue: 0.92, alpha: 1.0)
        m.metallic = .init(floatLiteral: 0.0)
        m.specular = .init(floatLiteral: 1.0)

        // 很轻的水膜，不做玻璃般的锐利镜面。
        m.clearcoat = .init(floatLiteral: 0.18)
        m.clearcoatRoughness = .init(floatLiteral: 0.16)

        // 诊断模式：实心不透明，用来判断"看不见"是材质问题还是几何/相机问题
        if ProcessInfo.processInfo.environment["ICE_SOLID"] == "1" {
            m.blending = .transparent(opacity: .init(floatLiteral: 0.95))
            m.roughness = .init(floatLiteral: 0.2)
            return m
        }

        if let colorTex = colorTexture, let opacityTex = opacityTexture, let roughTex = roughnessTexture {
            m.baseColor = .init(texture: MaterialParameters.Texture(colorTex))
            m.blending = .transparent(opacity: .init(texture: MaterialParameters.Texture(opacityTex)))
            m.roughness = .init(texture: MaterialParameters.Texture(roughTex))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: 0.34))
            m.roughness = .init(floatLiteral: 0.34)
        }

        return m
    }
}
