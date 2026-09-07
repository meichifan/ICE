//
//  ICEApp.swift
//  ICE
//
//  App 入口：只负责把全屏的 IceSceneView 放到 Window 里。
//  没有任何导航栏、工具栏、文字或设置。
//

import SwiftUI

@main
struct ICEApp: App {
    var body: some Scene {
        WindowGroup {
            IceSceneView()
                .ignoresSafeArea()
                .statusBarHidden(true)
        }
    }
}
