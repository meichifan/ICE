# ICE / 一块冰

一个极简数字玩具：打开 App，看到一块冰，伸手碰一下。

## 技术路线

- **Swift + SwiftUI**：App 生命周期与全屏容器
- **RealityKit（3D，非 AR 模式）**：真立方体网格 + PBR 材质 + 环境光照 + 手写惯性交互
- 不用 Metal 自定义着色器（留到需要"冰的体积感"时再补）
- 无第三方依赖

### 为什么是真 3D

贴图方案（一张照片当纹理）在静止时能看，但它是「某个瞬间、某个视角、某个光源」的记录：
不能转视角、光不随动作变、内部结构没有视差，而且**没有几何体**——
后续要做的融化、裂纹、碎裂一个都实现不了。所以改成真 3D 立方体。

## 项目结构

```
ICE/
├── App/ICEApp.swift            入口：全屏、隐藏状态栏
├── Views/IceSceneView.swift    SwiftUI ↔ RealityKit 桥（ARView .nonAR 模式）
├── Scene/IceScene.swift        场景：黑背景 + 环境光照 + 相机 + 灯光 + 冰块 + 倒影
├── Objects/IceCubeNode.swift   冰块：网格 + PBR 材质 + 程序化"清浊"贴图
├── Interaction/IceInteraction.swift  点击/拖动/惯性/旋转/触觉
└── Resources/
    ├── iceEnv.skybox/env.png   环境贴图（等距圆柱投影）：极暗房间 + 左上柔光箱
    └── Info.plist
```

### 关键实现说明

- **冰的观感** = clearcoat（表面水光的镜面高光）+ 清浊不均的透明度/粗糙度贴图。
  贴图用 Core Graphics 程序化生成，不依赖美术资源。
- **桌面倒影**：RealityKit 不做平面实时反射，用一块沿 Y 翻转的冰块副本实现
  （缩放 y 为负、材质压暗压淡），这是业界通用做法。
- **拖拽映射**：场景里放了一块不可见的平面，手指位置通过 hit test 精确映射到桌面上，
  所以拖动是 1:1 跟手的，不需要猜投影矩阵。
- **手感**：全部手动数值积分（跟随迟滞、速度上限、指数阻尼、边缘软停止、随速绕 Y 旋转）。
  没有用物理引擎，参数完全可控。

## 构建与安装（无需 Mac）

- 每次 push 到 `main`，GitHub Actions 会在云端 Mac 上：
  1. 产出未签名 `ICE.ipa`（Actions 页面的 **ICE-ipa** 构件）
  2. 在 iOS 模拟器里跑起来并截图（**ICE-screenshots** 构件）——用来在无 Mac 的情况下验收画面
- 安装到 iPhone：下载 IPA → Windows 上用 [Sideloadly](https://sideloadly.io) → 填 Apple ID → Start
  → 手机「设置 → 通用 → VPN与设备管理」信任证书 → 打开
- 免费签名 7 天有效，到期重装一次即可

## 配置

- Bundle ID: `com.ice.app`
- 最低系统: iOS 16
- 仅竖屏，隐藏状态栏

## 后续（按作者规划，尚未实现）

融化、水滴、裂纹、碎裂、摇晃、温度系统、每日物品、Widget、音效。
其中「冰的体积感」（次表面散射 / 内部折射）需要自定义着色器，
当前 iOS 17 SDK 的 `PhysicallyBasedMaterial` 未暴露次表面散射属性。
