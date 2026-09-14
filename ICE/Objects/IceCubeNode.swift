//
//  IceCubeNode.swift
//  ICE
//
//  冰块本体。
//
//  视觉使用一张真实冰块微距照片做成的纹理（Resources/ice_cube.png），
//  贴图自带 alpha：黑色桌面部分已经完全透明，只保留冰块本体的透光、
//  冰裂、气泡与冷白高光。下方再叠一层淡到几乎看不见的湿润反射
//  （Resources/ice_reflection.png），像冰块放在黑玻璃桌面上。
//
//  交互逻辑不在这里，见 IceInteraction.swift。
//

import SpriteKit

final class IceCubeNode: SKNode {

    /// 冰块的屏幕边长（点）
    static let edge: CGFloat = 200

    /// 反射贴图的高宽比（ice_reflection.png 为 1024 x 242）
    private static let reflectionAspect: CGFloat = 242.0 / 1024.0

    let bodySprite: SKSpriteNode
    private let reflectionSprite: SKSpriteNode

    override init() {
        let size = IceCubeNode.edge

        let bodyTexture = SKTexture(imageNamed: "ice_cube")
        bodyTexture.filteringMode = .linear
        bodySprite = SKSpriteNode(texture: bodyTexture)
        bodySprite.size = CGSize(width: size, height: size)

        let reflectionTexture = SKTexture(imageNamed: "ice_reflection")
        reflectionTexture.filteringMode = .linear
        reflectionSprite = SKSpriteNode(texture: reflectionTexture)

        let reflectionHeight = size * IceCubeNode.reflectionAspect
        reflectionSprite.size = CGSize(width: size, height: reflectionHeight)
        reflectionSprite.alpha = 0.85
        reflectionSprite.zPosition = -1

        super.init()

        // 反射紧贴冰块底边（叠一点，避免出现缝隙）
        reflectionSprite.position = CGPoint(x: 0,
                                            y: -size / 2 - reflectionHeight / 2 + 4)
        addChild(reflectionSprite)
        addChild(bodySprite)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
