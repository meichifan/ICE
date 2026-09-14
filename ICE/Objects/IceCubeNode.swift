//
//  IceCubeNode.swift
//  ICE
//
//  一块冰（真 3D）。
//
//  冰的观感来自三件事：
//   1. clearcoat —— 表面那层"水光"的冷白镜面高光
//   2. 清浊不均 —— 一张程序化贴图控制"哪里透、哪里浑"
//   3. 光滑与霜面不均 —— 另一张程序化贴图控制"哪里亮、哪里哑"
//
//  贴图全部用 Core Graphics 生成，不依赖任何美术资源。
//  （真正的"冰的体积感"——光进入冰体内部散射——需要自定义着色器，
//    本 SDK 的 PhysicallyBasedMaterial 未暴露次表面散射，留到后续阶段。）
//

import RealityKit
import UIKit

enum IceTextures {

    /// 透明度贴图：白＝不透明（浑浊），黑＝透明（清）
    static func opacityImage(side: CGFloat = 512) -> CGImage? {
        makeIceNoise(side: side,
                     base: 0.30,                 // 整体偏清透
                     blobCount: 70,
                     blobAlpha: 0.04...0.16,
                     blobScale: 0.05...0.26,
                     crackCount: 18,
                     crackAlpha: 0.10...0.26,
                     crackWidth: 0.6...1.8)
    }

    /// 粗糙度贴图：白＝粗糙（霜面、高光散），黑＝光滑（镜面、高光锐）
    static func roughnessImage(side: CGFloat = 512) -> CGImage? {
        makeIceNoise(side: side,
                     base: 0.14,                 // 整体光滑，高光锐利
                     blobCount: 55,
                     blobAlpha: 0.05...0.20,
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

            // 柔和的团块：冰内部的霜雾/浊区
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

            // 细小的冰裂：几条细线，给内部一点结构
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

final class IceCubeNode {

    /// 冰块尺寸（米）。真 3D 之后一切都用真实尺度。
    static let size: SIMD3<Float> = [0.09, 0.09, 0.09]

    /// 真实冰块是"带一点崩边的方"，棱角基本是锐的
    static let cornerRadius: Float = 0.002

    static func makeMesh() -> MeshResource {
        MeshResource.generateBox(size: size, cornerRadius: cornerRadius)
    }

    /// 冰体本体
    static func makeBody() -> ModelEntity {
        let entity = ModelEntity(mesh: makeMesh(), materials: [iceMaterial()])
        entity.name = IceScene.cubeName
        entity.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        return entity
    }

    /// 桌面上的倒影：同一个网格沿 Y 翻转，材质压暗压淡
    static func makeReflection() -> ModelEntity {
        var material = iceMaterial()
        material.blending = .transparent(opacity: .init(floatLiteral: 0.40))
        material.baseColor.tint = UIColor(white: 0.68, alpha: 1.0)
        let entity = ModelEntity(mesh: makeMesh(), materials: [material])
        entity.name = IceScene.mirrorName
        entity.scale = [1, -1, 1]
        return entity
    }

    // MARK: - 冰材质

    static func iceMaterial() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()

        m.baseColor.tint = UIColor(red: 0.90, green: 0.95, blue: 1.00, alpha: 1.0)
        m.metallic = .init(floatLiteral: 0.0)
        m.specular = .init(floatLiteral: 0.75)

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

        iceLog("opacity texture: \(opacityMap != nil), roughness texture: \(roughnessMap != nil)")

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
