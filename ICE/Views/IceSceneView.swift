//
//  IceSceneView.swift
//  ICE
//
//  SwiftUI 与 SpriteKit 之间的桥。
//  整个视图就是一个全屏 SpriteView，场景尺寸跟随设备屏幕。
//

import SwiftUI
import SpriteKit

struct IceSceneView: View {
    var body: some View {
        GeometryReader { geo in
            SpriteView(scene: makeScene(size: geo.size))
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    private func makeScene(size: CGSize) -> IceScene {
        let scene = IceScene(size: size)
        scene.scaleMode = .resizeFill
        return scene
    }
}

#Preview {
    IceSceneView()
}
