# Skills Pet macOS

一个用 `Swift + AppKit` 写的轻量级 macOS 桌宠项目。

它以原生 `AppKit` 方式运行，不依赖 Storyboard，也不依赖 SwiftUI。当前版本已经具备透明悬浮窗、拖拽交互、右键菜单、状态栏入口，以及多种猫咪姿态和简单动态效果，适合作为一个桌宠原型项目继续扩展。

## Preview

- 透明无边框悬浮窗
- 可拖拽、可自动保持可见
- 支持行走、睡觉、坐姿、趴卧等多种状态
- 双击可打开本地 Skills Hub
- 右键菜单和状态栏菜单可快速操作

项目内资源示例位于：

- `cat-sprites/`
- `cat-picture/`

## Features

- 原生 `AppKit` 桌面宠物窗口
- `NSPanel` 透明悬浮、跨 Space 显示
- 鼠标拖拽与释放后的惯性过渡
- 右键菜单操作
- macOS 状态栏菜单入口
- 多姿态切换与简单逐帧动画
- 眨眼、尾巴摆动、耳朵 twitch、拉伸等细节动作
- 本地 HTML catalog / hub 自动发现与打开

## Project Structure

```text
.
├── Sources/
│   ├── main.swift              # 应用入口
│   ├── AppDelegate.swift       # 状态栏、窗口守护、外部资源路径
│   ├── PetWindow.swift         # 悬浮窗定义与窗口行为
│   └── PetView.swift           # 桌宠绘制、状态机、交互与动画
├── SkillsPetLite.xcodeproj/    # Xcode 工程
├── SkillsPetLite/              # Info.plist / Assets
├── cat-sprites/                # 桌宠精灵图
├── cat-picture/                # 项目素材图片 / 视频
├── scripts/
│   ├── build.sh                # 命令行构建 .app
│   └── clean_sprite_edges.py   # 精灵图处理脚本
└── launch.command              # 快速打开 Xcode 工程
```

## Run

### Option 1: Open in Xcode

1. 双击 `launch.command`
2. 或手动打开 `SkillsPetLite.xcodeproj`
3. 选择 `SkillsPetLite` target 后运行

### Option 2: Build from script

```bash
bash scripts/build.sh
```

构建完成后，产物默认位于：

```text
build/SkillsPetLite.app
build/SkillsPetLite-bin
```

## Interaction

- 单击并拖拽：移动桌宠
- 双击：打开本地 Skills Hub
- 右键：打开快捷菜单
- 状态栏菜单：显示桌宠、重新居中、打开 Hub / Catalog、退出

## Local Catalog Integration

程序会优先尝试查找或生成以下页面：

- `skills_hub.html`
- `skills_catalog.html`

查找逻辑在本地目录中进行；如果没有找到，会在：

```text
~/Library/Caches/SkillsPetLite/
```

下生成一个基础的本地 catalog 页面。

猫咪精灵图默认从以下目录读取：

```text
~/Desktop/skills-pet-macos/cat-sprites
```

如果磁盘路径不可用，程序会回退到 App Bundle 中的资源。

## Tech Stack

- Swift
- AppKit
- Xcode project
- Shell scripts for local build

## Current Status

当前项目更偏向一个可运行的原型版本，已经具备基础交互和动画能力，适合继续往这些方向扩展：

- 增加更多动作状态与帧动画
- 增加点击反馈和情绪系统
- 接入配置面板
- 支持更多本地工具入口
- 完善资源打包与发布流程

## Known Notes

- 这是一个 macOS 项目，只能在 macOS 环境运行
- 某些本地 Hub / Catalog 能力依赖你机器上的本地文件结构
- 如果你的 Xcode / Command Line Tools 版本较旧，构建可能需要额外调整

## License

如果你准备公开到 GitHub，建议补充一个正式的开源许可证，例如 `MIT`。
