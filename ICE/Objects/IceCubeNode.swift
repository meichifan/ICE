//
//  IceCubeNode.swift
//  ICE
//
//  一块冰（真 3D）。
//
//  冰的观感来自三件事：
//   1. clearcoat —— 冷白、锐利的镜面高光（表面那层"湿润的水光"）
//   2. subsurface scattering —— 光进入冰体、在里面散射、再透出来。
//      这是"冰"和"玻璃"的本质区别，也是路线 2 能拿到的最大收益。
//   3. 云雾贴图 —— 一块冰里清与浊的分布，同时当作透明度贴图和粗糙度贴图：
//      清的地方透、滑；浊的地方浑、霜。
//
//  贴图全部程序化生成（Core Graphics），不依赖任何美术资源。
//

import RealityKit
import UIKit

enum IceTextures {

    /// "云雾"贴图：白色＝浑浊/不透明/粗糙，黑色＝清透/光滑
    static func cloudImage(side: CGFloat = 512) -> CGImage? {
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)

            // 基底：整体偏清透
            cg.setFillColor(UIColor(white: 1.0, alpha: 0.42).cgColor)
            cg.fill(rect)

            // 浑浊团块：冰内部不均匀的霜雾
            for _ in 0..<110 {
                let r = CGFloat.random(in: side * 0.04...side * 0.24)
                let x = CGFloat.random(in: 0...side)
                let y = CGFloat.random(in: 0...side)
                let a = CGFloat.random(in: 0.03...0.20)
                let colors = [
                    UIColor(white: 1.0, alpha: a).cgColor,
                    UIColor(white: 1.0, alpha: 0).cgColor
                ] as CFArray
                let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors, locations: [0, 1])!
                cg.drawRadialGradient(grad,
                                      startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                      endCenter: CGPoint(x: x, y: y), endRadius: r,
                                      options: [])
            }

            // 裂隙：细长的暗线，让内部有结构
            cg.setLineCap(.round)
            for _ in 0..<34 {
                let x0 = CGFloat.random(in: 0...side)
                let y0 = CGFloat.random(in: 0...side)
                let len = CGFloat.random(in: side * 0.06...side * 0.30)
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x0, y: y0))
                path.addLine(to: CGPoint(x: x0 + cos(angle) * len,
                                         y: y0 + sin(angle) * len))
                path.lineWidth = CGFloat.random(in: 0.8...2.4)
                UIColor(white: 0.0, alpha: CGFloat.random(in: 0.10...0.34)).setStroke()
                path.stroke()
            }

            // 边缘稍微更清透一点（冰的外层更干净）
            let clear = [
                UIColor(white: 1.0, alpha: 0.0).cgColor,
                UIColor(white: 1.0, alpha: 0.0).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: clear, locations: [0, 1]) {
                cg.drawLinearGradient(grad, start: .zero, end: .zero, options: [])
            }
        }
        return image.cgImage
    }

    /// 环境光照贴图（等距圆柱投影）：一间极暗的房间里，左上有一块柔和的主光。
    /// 它不会显示成背景，只用来给冰块提供反射和高光。
    static func environmentImage(width: Int = 1024, height: Int = 512) -> CGImage? {
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)

            // 极暗的房间：上略亮、下最暗
            let colors = [
                UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1).cgColor,
                UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1).cgColor,
                UIColor(red: 0.01, green: 0.01, blue: 0.015, alpha: 1).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 0.55, 1]) {
                cg.drawLinearGradient(grad,
                                      start: CGPoint(x: 0, y: 0),
                                      end: CGPoint(x: 0, y: rect.height),
                                      options: [])
            }

            // 主光（柔光箱）：左上前方
            drawSoftLight(cg, center: CGPoint(x: rect.width * 0.30, y: rect.height * 0.30),
                          radius: rect.width * 0.20, intensity: 0.95)
            // 副光：右侧稍弱，给冰的另一条棱一点亮
            drawSoftLight(cg, center: CGPoint(x: rect.width * 0.72, y: rect.height * 0.40),
                          radius: rect.width * 0.14, intensity: 0.42)
            // 极弱的顶部环境光
            drawSoftLight(cg, center: CGPoint(x: rect.width * 0.50, y: rect.height * 0.06),
                          radius: rect.width * 0.30, intensity: 0.16)
        }
        return image.cgImage
    }

    private static func drawSoftLight(_ cg: CGContext,
                                      center: CGPoint,
                                      radius: CGFloat,
                                      intensity: CGFloat) {
        let colors = [
            UIColor(red: 1.0, green: 0.99, blue: 0.97, alpha: intensity).cgColor,
            UIColor(red: 0.9, green: 0.94, blue: 1.0, alpha: intensity * 0.35).cgColor,
            UIColor(white: 1.0, alpha: 0).cgColor
        ] as CFArray
        guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: colors, locations: [0, 0.4, 1]) else { return }
        cg.drawRadialGradient(grad,
                              startCenter: center, startRadius: 0,
                              endCenter: center, endRadius: radius,
                              options: [])
    }

    /// CGImage -> TextureResource
    static func texture(from image: CGImage) -> TextureResource? {
        try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }
}

final class IceCubeNode {

    /// 冰块尺寸（米）。真 3D 之后一切都用真实尺度。
    static let size: SIMD3<Float> = [0.09, 0.09, 0.09]
    static let cornerRadius: Float = 0.0055

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
        material.blending = .transparent(opacity: .init(floatLiteral: 0.45))
        material.baseColor.tint = UIColor(white: 0.72, alpha: 1.0)
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
        m.roughness = .init(floatLiteral: 0.05)
        m.specular = .init(floatLiteral: 0.55)

        // 表面那层水光的镜面反射
        m.clearcoat = .init(floatLiteral: 1.0)
        m.clearcoatRoughness = .init(floatLiteral: 0.04)

        // 冰的体积感：光进入冰体再散出来
        m.subsurfaceColor = .init(tint: UIColor(red: 0.74, green: 0.89, blue: 1.00, alpha: 1.0))
        m.subsurfaceWeight = .init(floatLiteral: 0.65)
        m.subsurfaceRadius = .init(floatLiteral: 0.012)

        // 清浊不均
        if let image = IceTextures.cloudImage(), let resource = IceTextures.texture(from: image) {
            let cloud = MaterialParameters.Texture(resource)
            m.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(texture: cloud))
            m.roughness = PhysicallyBasedMaterial.Roughness(texture: cloud)
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: 0.62))
        }

        return m
    }
}
