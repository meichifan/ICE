//
//  IceCubeNode.swift
//  ICE
//
//  冰块本体。
//
//  视觉完全用 Core Graphics 程序化绘制（不依赖任何图片资源）：
//  - 近乎透明的冷白玻璃体，带轻微不规则圆角
//  - 内部气泡、朦胧水汽（frost）
//  - 边缘折射亮线 + 顶部冷白高光
//  - 底部淡淡的湿润反射（作为子节点，随冰块一起移动/缩放）
//
//  交互逻辑不在这里，见 IceInteraction.swift。
//

import SpriteKit
import UIKit

final class IceCubeNode: SKNode {

    /// 冰块边长（屏幕点）
    static let edge: CGFloat = 190

    let bodySprite: SKSpriteNode
    private let reflectionSprite: SKSpriteNode

    override init() {
        let size = IceCubeNode.edge
        bodySprite = SKSpriteNode(texture: IceCubeNode.makeIceTexture(size: size))
        bodySprite.size = CGSize(width: size, height: size)

        reflectionSprite = SKSpriteNode(texture: IceCubeNode.makeReflectionTexture(size: size))
        let rSize = CGSize(width: size * 0.94, height: size * 0.30)
        reflectionSprite.size = rSize
        reflectionSprite.position = CGPoint(x: 0, y: -size / 2 - rSize.height / 2 + 6)
        reflectionSprite.alpha = 0.55
        reflectionSprite.zPosition = -1

        super.init()

        addChild(reflectionSprite)
        addChild(bodySprite)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 冰块贴图（程序化绘制）

    static func makeIceTexture(size: CGFloat) -> SKTexture {
        let s = size * 2 // 2x 渲染，保证清晰
        let rect = CGRect(x: 0, y: 0, width: s, height: s)
        let renderer = UIGraphicsImageRenderer(size: rect.size)

        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let corner = s * 0.18

            // 主体路径：圆角略带不规则感
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: s * 0.015, dy: s * 0.015),
                                    cornerRadius: corner)
            cg.addPath(path.cgPath)
            cg.clip()

            // 1. 基体：接近透明的冷白，自上而下微微变暗（内部深度感）
            let baseColors = [
                UIColor(white: 1.0, alpha: 0.20).cgColor,
                UIColor(red: 0.85, green: 0.92, blue: 0.98, alpha: 0.10).cgColor,
                UIColor(red: 0.75, green: 0.85, blue: 0.95, alpha: 0.16).cgColor
            ] as CFArray
            let baseGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: baseColors,
                                      locations: [0.0, 0.55, 1.0])!
            cg.drawLinearGradient(baseGrad,
                                  start: CGPoint(x: 0, y: rect.maxY),
                                  end: CGPoint(x: 0, y: rect.minY),
                                  options: [])

            // 2. 内部朦胧水汽（frost）：几块柔和的冷白雾斑
            cg.saveGState()
            for _ in 0..<7 {
                let fx = CGFloat.random(in: rect.width * 0.15...rect.width * 0.85)
                let fy = CGFloat.random(in: rect.height * 0.15...rect.height * 0.85)
                let fr = CGFloat.random(in: s * 0.10...s * 0.26)
                let alpha = CGFloat.random(in: 0.05...0.13)
                let frostColors = [
                    UIColor(white: 1.0, alpha: alpha).cgColor,
                    UIColor(white: 1.0, alpha: 0).cgColor
                ] as CFArray
                let frostGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                           colors: frostColors,
                                           locations: [0.0, 1.0])!
                cg.drawRadialGradient(frostGrad,
                                      startCenter: CGPoint(x: fx, y: fy), startRadius: 0,
                                      endCenter: CGPoint(x: fx, y: fy), endRadius: fr,
                                      options: [])
            }
            cg.restoreGState()

            // 3. 内部气泡：大小不一的白色小圆点，带柔和光晕
            for _ in 0..<26 {
                let bx = CGFloat.random(in: rect.width * 0.12...rect.width * 0.88)
                let by = CGFloat.random(in: rect.height * 0.12...rect.height * 0.88)
                let br = CGFloat.random(in: s * 0.004...s * 0.018)
                let alpha = CGFloat.random(in: 0.12...0.35)

                let bubbleColors = [
                    UIColor(white: 1.0, alpha: alpha * 0.5).cgColor,
                    UIColor(white: 1.0, alpha: 0).cgColor
                ] as CFArray
                let bubbleGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: bubbleColors,
                                            locations: [0.0, 1.0])!
                cg.drawRadialGradient(bubbleGrad,
                                      startCenter: CGPoint(x: bx, y: by), startRadius: 0,
                                      endCenter: CGPoint(x: bx, y: by), endRadius: br * 2.2,
                                      options: [])
                cg.setFillColor(UIColor(white: 1.0, alpha: alpha).cgColor)
                cg.fillEllipse(in: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2))
            }

            // 4. 对角光带：微弱的折射斜光
            cg.saveGState()
            let bandColors = [
                UIColor(white: 1.0, alpha: 0).cgColor,
                UIColor(white: 1.0, alpha: 0.07).cgColor,
                UIColor(white: 1.0, alpha: 0).cgColor
            ] as CFArray
            let bandGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: bandColors,
                                      locations: [0.0, 0.5, 1.0])!
            cg.translateBy(x: rect.midX, y: rect.midY)
            cg.rotate(by: -.pi / 4)
            cg.drawLinearGradient(bandGrad,
                                  start: CGPoint(x: -s * 0.30, y: 0),
                                  end: CGPoint(x: s * 0.10, y: 0),
                                  options: [])
            cg.restoreGState()

            // 5. 边缘折射亮线：沿路径描一层半透明白
            cg.saveGState()
            cg.addPath(path.cgPath)
            cg.setStrokeColor(UIColor(white: 1.0, alpha: 0.28).cgColor)
            cg.setLineWidth(s * 0.012)
            cg.strokePath()
            cg.restoreGState()

            // 6. 内阴影：底部和右侧压暗，增加体积感
            let shadowColors = [
                UIColor(red: 0.55, green: 0.68, blue: 0.82, alpha: 0.16).cgColor,
                UIColor(red: 0.55, green: 0.68, blue: 0.82, alpha: 0).cgColor
            ] as CFArray
            let shadowGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: shadowColors,
                                        locations: [0.0, 1.0])!
            cg.drawLinearGradient(shadowGrad,
                                  start: CGPoint(x: 0, y: rect.minY),
                                  end: CGPoint(x: 0, y: rect.minY + s * 0.30),
                                  options: [])

            // 7. 顶部高光：一道锐利 + 一层柔和的冷白
            let hlColors = [
                UIColor(white: 1.0, alpha: 0.55).cgColor,
                UIColor(white: 1.0, alpha: 0).cgColor
            ] as CFArray
            let hlGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: hlColors,
                                    locations: [0.0, 1.0])!
            // 柔和高光
            cg.drawRadialGradient(hlGrad,
                                  startCenter: CGPoint(x: rect.midX - s * 0.12, y: rect.maxY - s * 0.10),
                                  startRadius: 0,
                                  endCenter: CGPoint(x: rect.midX - s * 0.12, y: rect.maxY - s * 0.10),
                                  endRadius: s * 0.34,
                                  options: [])
            // 锐利高光点
            let sharpColors = [
                UIColor(white: 1.0, alpha: 0.75).cgColor,
                UIColor(white: 1.0, alpha: 0).cgColor
            ] as CFArray
            let sharpGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: sharpColors,
                                       locations: [0.0, 1.0])!
            cg.drawRadialGradient(sharpGrad,
                                  startCenter: CGPoint(x: rect.midX - s * 0.16, y: rect.maxY - s * 0.08),
                                  startRadius: 0,
                                  endCenter: CGPoint(x: rect.midX - s * 0.16, y: rect.maxY - s * 0.08),
                                  endRadius: s * 0.09,
                                  options: [])
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    // MARK: - 湿润反射贴图

    static func makeReflectionTexture(size: CGFloat) -> SKTexture {
        let w = size * 2 * 0.94
        let h = size * 2 * 0.30
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        let renderer = UIGraphicsImageRenderer(size: rect.size)

        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            // 椭圆形的淡白湿痕，中心稍亮，向外淡出
            let colors = [
                UIColor(white: 1.0, alpha: 0.16).cgColor,
                UIColor(white: 1.0, alpha: 0.05).cgColor,
                UIColor(white: 1.0, alpha: 0).cgColor
            ] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors,
                                  locations: [0.0, 0.5, 1.0])!
            cg.saveGState()
            cg.translateBy(x: rect.midX, y: rect.midY)
            cg.scaleBy(x: rect.width / rect.height, y: 1.0) // 拉成椭圆
            let r = rect.height / 2
            cg.drawRadialGradient(grad,
                                  startCenter: .zero, startRadius: 0,
                                  endCenter: .zero, endRadius: r,
                                  options: [])
            cg.restoreGState()
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}
