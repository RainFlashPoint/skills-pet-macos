# Skills Pet macOS

一个用 `Swift + AppKit` 写的原生 macOS 桌宠项目。

它当前是一个轻量、可运行、可继续扩展的桌宠原型：透明悬浮窗、拖拽交互、状态栏入口、右键菜单、多姿态切换，以及基础动画细节都已经打通。

![Skills Pet Preview](docs/assets/github-preview.jpg)

## Overview

- 原生 `AppKit` 实现，不依赖 Storyboard
- 透明无边框悬浮窗，跨 Space 显示
- 支持拖拽、双击、右键菜单、状态栏菜单
- 包含 `walk`、`sleep`、`sit`、`loaf`、`recline` 等姿态
- 支持从单张本地图片生成自定义宠物素材包
- 可自动打开本地 `Skills Hub` / `Skills Catalog`

## Features

- `NSPanel` 浮动窗口与可见性守护
- 拖拽跟随与释放后的惯性回弹
- 逐帧精灵动画与状态切换
- 眨眼、尾巴摆动、耳朵 twitch、拉伸等细节动作
- 单图导入生成程序化动作素材包
- 本地 HTML 页面自动发现与兜底生成
- Xcode 工程和命令行构建脚本两套启动方式

## Preview Assets

- GitHub 预览图：`docs/assets/github-preview.jpg`
- 桌宠精灵图：`cat-sprites/`
- 原始参考素材：`cat-picture/`

## Project Structure

```text
.
├── Sources/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── PetWindow.swift
│   └── PetView.swift
├── SkillsPetLite.xcodeproj/
├── SkillsPetLite/
├── cat-sprites/
├── cat-picture/
├── docs/
│   ├── assets/
│   └── releases/
├── scripts/
├── LICENSE
├── RELEASING.md
└── launch.command
```

## Getting Started

### Open with Xcode

```bash
open SkillsPetLite.xcodeproj
```

或者直接双击：

```text
launch.command
```

### Build from script

```bash
bash scripts/build.sh
```

默认产物：

```text
build/SkillsPetLite.app
build/SkillsPetLite-bin
```

## Interaction

- 拖拽：移动桌宠
- 双击：打开本地 `Skills Hub`
- 右键：打开快捷菜单
- 状态栏菜单：显示桌宠、居中桌宠、打开 Hub / Catalog、退出
- 状态栏 `Import Pet Image...`：打开导入工作台，添加参考图并配置生成提示词
- 状态栏 `AI 模型设置...`：配置 AI 增强生成的供应商、模型、Endpoint、质量模式和 API Key
- 状态栏 `Use Default Cat`：切回内置默认猫素材
- 状态栏 `语言 / Language`：在中文和英文界面之间切换，默认中文
- 模式切换：`自由乱动` / `右下角停靠`

## Local Integration

程序会优先尝试读取：

- `skills_hub.html`
- `skills_catalog.html`

如果没有找到，会在下面这个目录生成一个基础版本：

```text
~/Library/Caches/SkillsPetLite/
```

精灵图默认读取目录：

```text
~/Desktop/skills-pet-macos/cat-sprites
```

如果磁盘路径不可用，程序会自动回退到 App Bundle 资源。

## Local Pet Packs

现在支持最简单的本地宠物素材包模式，不用改代码。

也可以从状态栏菜单点击 `Import Pet Image...` 打开导入工作台。支持添加多张 `png`、`jpg`、`jpeg`、`heic`、`tiff` 或 `webp` 参考图，并配置宠物名称、视觉风格和提示词备注。程序当前会：

- 保存多图和提示词配置到 `import-config.json`
- 使用第一张参考图作为本地免费兜底输入
- 裁剪透明边或简单白色背景边缘
- 在 macOS 14+ 上优先尝试 Apple Vision 前景分割抠图
- 生成 `recline`、`loaf`、`sit`、`sleep` 和 `walk_01` 到 `walk_06`
- 写入 `~/SkillsPetLite/pets/<image-name>/`
- 展示大尺寸预览面板，对比原图、生成姿态和 walk 动态循环，确认后才切换到新宠物
- 取消预览时自动删除这次生成的候选素材包

如果生成效果不理想，可以从状态栏点击 `Use Default Cat` 切回默认猫。

这是本地程序化生成，不依赖云端模型。它会优先使用系统 Vision 能力做前景分割，再用缩放、压扁、偏移、旋转和当前动画状态机制造动作感；如果要生成真实语义姿态，可以在后续接入可选模型管线。代码里已经把素材生成抽象成 `PetAssetGenerating`，后续可以用 API 模型实现替换当前本地生成器。

## AI Model Settings

状态栏菜单里的 `AI 模型设置...` 已经可以保存模型配置：

- 启用 / 关闭 AI 增强
- 供应商：OpenAI、fal.ai、Replicate、自定义
- 模型名称
- Endpoint URL
- 质量模式
- API Key

API Key 会保存到 macOS Keychain；其它配置保存到 `UserDefaults`。当前 `测试配置` 只检查必填项，不会发起网络请求；真实 API 调用会在后续 `ModelPetPackGenerator` 中接入。

把你自己的宠物素材放到：

```text
~/SkillsPetLite/pets/<your-pet-name>/
```

程序会自动扫描 `pets/` 下第一个可用目录，并优先读取里面的图片；缺的帧会自动回退到默认 `cat-sprites/`。

推荐文件名：

```text
recline.png
loaf.png
sit.png
sleep.png
walk_01.png
walk_02.png
walk_03.png
walk_04.png
walk_05.png
walk_06.png
```

也兼容当前项目默认文件名，例如：

```text
cat_idle_recline_v1.png
cat_idle_loaf_v1.png
cat_sit_v1.png
cat_sleep_curl_v1.png
cat_walk_01_v1.png
...
cat_walk_04_v1.png
```

建议：

- 优先用透明背景 PNG
- `walk_01` 到 `walk_06` 尺寸和落脚点尽量一致
- 就算只放一部分图也能启动，缺失的姿态会回退到默认猫素材

## Tech Stack

- Swift
- AppKit
- Xcode
- Shell

## Release

- 最新发布说明：`docs/releases/v0.1.1.md`
- 首个发布说明：`docs/releases/v0.1.0.md`
- 发布流程说明：`RELEASING.md`

## Known Limitations

- 仅支持 macOS
- 当前仍是原型版本
- 部分本地 Hub / Catalog 功能依赖本机文件结构
- 老版本 Xcode 或 Command Line Tools 可能需要额外调整

## License

This project is licensed under the MIT License. See `LICENSE`.
