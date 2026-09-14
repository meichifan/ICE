//
//  IceCubeNode.swift
//  ICE
//
//  一块冰（真 3D）。
//
//  这里做三件事：
//   1. 程序化生成"不规则冰块"网格：在标准立方体上做顶点扰动 + 法线扰动，
//      轮廓不再是规则方盒，表面也不再是镜面平板。
//   2. 冰材质：clearcoat（表面水光的锐利高光）+ 清浊不均的透明度贴图
//      + 光滑/霜面不均的粗糙度贴图。
//   3. 桌面倒影：一块沿 Y 翻转的冰块，分成若干层、越往下越透明，
//      做出"湿痕向下淡出"的感觉（RealityKit 不做平面实时反射）。
//
//  所有贴图都用 Core Graphics 程序化生成，不依赖任何美术资源。
//

import RealityKit
import UIKit

// MARK: - 程序化贴图

enum IceTextures {

    /// 透明度贴图：白＝不透明（浑浊），黑＝透明（清）
    static func opacityImage(side: CGFloat = 512) -> CGImage? {
        makeIceNoise(side: side,
                     base: 0.26,                 // 整体偏清透
                     blobCount: 70,
                     blobAlpha: 0.04...0.16,
                     blobScale: 0.05...0.26,
                     crackCount: 18,
                     crackAlpha: 0.10...0.26,
                     crackWidth: 0.6...1.8)
    }

    /// 粗糙度贴图：白＝粗糙（霜面），黑＝光滑（镜面）
    static func roughnessImage(side: CGFloat = 512) -> CGImage? {
        makeIceNoise(side: side,
                     base: 0.12,
                     blobCount: 55,
                     blobAlpha: 0.05...0.22,
                     blobScale: 0.04...0.20,
                     crackCount: 10,
                     crackAlpha: 0.08...0.20,
                     crackWidth: 0.5...1.4)
    }

    private static func makeIceNoise(side: CGFloat,
                                     base: CGFloat,
                                     blobCount: Int,
                                     blobAlpha: ClosedRange<CGFloat>,
                                     blobScale: ClosedRange<CGFloat>,
                                     crackCount: Int,
                                     crackAlpha: ClosedRange<CGFloat>,
                                     crackWidth: ClosedRange<CGFloat>) -> CGImage? {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(white: base, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // 冰内部的霜雾团块
            for _ in 0..<blobCount {
                let r = CGFloat.random(in: side * blobScale.lowerBound...side * blobScale.upperBound)
                let x = CGFloat.random(in: 0...side)
                let y = CGFloat.random(in: 0...side)
                let a = CGFloat.random(in: blobAlpha)
                let colors = [
                    UIColor(white: 1.0, alpha: a).cgColor,
                    UIColor(white: 1.0, alpha: 0).cgColor
                ] as CFArray
                guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: [0, 1]) else { continue }
                cg.drawRadialGradient(grad,
                                      startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                      endCenter: CGPoint(x: x, y: y), endRadius: r,
                                      options: [])
            }

            // 细小的冰裂
            cg.setLineCap(.round)
            for _ in 0..<crackCount {
                let x0 = CGFloat.random(in: 0...side)
                let y0 = CGFloat.random(in: 0...side)
                let len = CGFloat.random(in: side * 0.05...side * 0.22)
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x0, y: y0))
                path.addLine(to: CGPoint(x: x0 + cos(angle) * len,
                                         y: y0 + sin(angle) * len))
                path.lineWidth = CGFloat.random(in: crackWidth)
                UIColor(white: 1.0, alpha: CGFloat.random(in: crackAlpha)).setStroke()
                path.stroke()
            }
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

    /// 平滑值噪声
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

    /// 在立方体表面做顶点扰动，得到一个"带崩边、表面不规整"的冰块。
    /// 失败返回 nil（调用方会退回标准方盒，保证一定能跑）。
    static func makeIrregularBox(size: SIMD3<Float>, segments: Int = 14) -> MeshResource? {
        let half = size / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        let faces: [(axis: Int, sign: Float)] = [(0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1)]
        let n = segments

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

                    // 大尺度起伏（整块冰的不规则）+ 小尺度碎面（冻结的粗糙表面）
                    let big = (noise(p * 9.0) - 0.5) * 0.0042
                    let small = (noise(p * 38.0 + SIMD3(11, 5, 7)) - 0.5) * 0.0016
                    // 棱边处收一点，做出"崩边"的感觉
                    let edge = min(min(1 - abs(fu), 1 - abs(fv)), 1)
                    let chip = (1 - edge) * edge * (noise(p * 24 + SIMD3(3, 17, 9)) - 0.5) * 0.0032
                    p += normal * (big + small + chip)

                    // 法线扰动：让高光在表面碎开，不再是一块平板
                    let grad = SIMD3<Float>(
                        noise(p * 46 + SIMD3(1, 0, 0)) - 0.5,
                        noise(p * 46 + SIMD3(0, 1, 0)) - 0.5,
                        noise(p * 46 + SIMD3(0, 0, 1)) - 0.5
                    )
                    normal = simd_normalize(normal + grad * 0.55)

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

    /// 桌面上的倒影：分层，越往下越淡，做出湿痕向下淡出的感觉。
    /// 返回一个容器（整体沿 Y 翻转），内部是若干层薄片。
    static func makeReflection() -> Entity {
        let container = Entity()
        container.name = IceScene.mirrorName
        container.scale = [1, -1, 1]

        let layers = 6
        let layerHeight = size.y / Float(layers)
        let opacityTop: Float = 0.26

        for k in 0..<layers {
            // 容器本地 +y 对应世界方向的下方（因为容器被翻转）
            let localY = -size.y / 2 + layerHeight * (Float(k) + 0.5)
            let t = Float(k) / Float(layers - 1)
            let opacity = opacityTop * pow(1 - t, 1.6) + 0.015

            var material = iceMaterial()
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            material.baseColor.tint = UIColor(white: 0.7, alpha: 1.0)

            let slab = ModelEntity(
                mesh: .generateBox(size: [size.x * 0.92, layerHeight, size.z * 0.92]),
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

        m.baseColor.tint = UIColor(red: 0.90, green: 0.95, blue: 1.00, alpha: 1.0)
        m.metallic = .init(floatLiteral: 0.0)
        m.specular = .init(floatLiteral: 0.85)

        // 表面那层水光的镜面反射
        m.clearcoat = .init(floatLiteral: 1.0)
        m.clearcoatRoughness = .init(floatLiteral: 0.03)

        // 诊断模式：实心不透明，用来判断"看不见"是材质问题还是几何/相机问题
        if ProcessInfo.processInfo.environment["ICE_SOLID"] == "1" {
            m.blending = .transparent(opacity: .init(floatLiteral: 0.95))
            m.roughness = .init(floatLiteral: 0.2)
            return m
        }

        // 清浊 / 光滑不均
        let opacityMap = IceTextures.opacityImage().flatMap { IceTextures.texture(from: $0) }
        let roughnessMap = IceTextures.roughnessImage().flatMap { IceTextures.texture(from: $0) }

        if let opacityMap {
            m.blending = .transparent(opacity: .init(texture: MaterialParameters.Texture(opacityMap)))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: 0.42))
        }

        if let roughnessMap {
            m.roughness = .init(texture: MaterialParameters.Texture(roughnessMap))
        } else {
            m.roughness = .init(floatLiteral: 0.12)
        }

        return m
    }
}
