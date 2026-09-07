# ICE / 一块冰

一个极简数字玩具：打开 App，看到一块冰，伸手碰一下。

## 构建

本仓库配置了 GitHub Actions，每次 push 到 `main` 分支会自动在云端 Mac 上编译出未签名的 `ICE.ipa`，在 Actions 运行页面的 Artifacts 里下载（zip 格式，约保留 30 天）。

## 安装到 iPhone（Windows，无需 Mac）

1. 下载并安装 [Sideloadly](https://sideloadly.io)（免费）。
2. iPhone 用数据线连上电脑，信任此电脑。
3. 打开 Sideloadly，拖入下载的 `ICE.ipa`，填入你的 Apple ID，点 Start。
4. 首次安装后，在 iPhone 上：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID。
5. 打开 ICE。

免费 Apple ID 签名 7 天有效，到期后用 Sideloadly 重新安装一次即可。

## 项目结构

```
ICE/
├── App/ICEApp.swift            App 入口
├── Views/IceSceneView.swift    SwiftUI ↔ SpriteKit 桥
├── Scene/IceScene.swift        场景：背景 + 冰块 + 触摸转发
├── Objects/IceCubeNode.swift   冰块（程序化绘制：气泡/水汽/高光/反射）
├── Interaction/IceInteraction.swift  点击/拖动/惯性/触觉反馈
└── Resources/Info.plist
```

- Bundle ID: `com.ice.app`
- 最低系统: iOS 16
- 无第三方依赖
