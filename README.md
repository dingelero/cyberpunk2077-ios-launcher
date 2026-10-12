# Cyberpunk2077 on iOS

免费、非官方的 Cyberpunk 2077 移动端启动器。使用自行准备的 Steam macOS ARM64 游戏文件，提供 540p / 720p / 1080p 全屏输出选项、触控和实体手柄输入（包括 DualSense 自适应扳机）。

- 当前发布：**0.9.2 / build 20，540p 启动修复 v8**
- 已有游玩测试记录：**iPhone 16 Pro Max，iOS 27**
- 其他 iOS / iPadOS 版本和机型：**兼容性未确认**，设备预设和自动识别不代表已经通过真机测试
- 硬件建议：A17 Pro / M2 及以上，具体机型仍需真机验证
- 游戏文件：Steam macOS 2.31 ARM64 版，需要自行准备

[下载 IPA](https://github.com/dingelero/cyberpunk2077-ios-launcher/releases/latest) · [安装与资源导入教程（中文 / English）](docs/DingElero启动器-使用教程.md) · [本版发布说明](docs/releases/v0.9.2.md)

本版针对 v7 的分辨率初始化问题加入修复和配置迁移，开放设备比例的 540p 模式。已完成构建、参数迁移和模拟器组件检查；本次 v8 IPA 尚未完成完整真机游玩验收。持续帧率、发热、HDR 和各机型可玩性需要实测，不承诺固定帧率。包内最低安装声明为 18.0，实际游玩测试范围仅为 iOS 27。

## 游戏截图（iPhone 16 Pro Max，开发期间记录）

以下为开发期间的实机截图，短时基准测试不代表本版或其他设备的持续性能。

**实机游戏画面**

![实机游戏画面](docs/screenshots/gameplay.png)

**驾驶画面**

![驾驶画面](docs/screenshots/driving.png)


**游戏内基准测试**

![游戏内基准测试](docs/screenshots/benchmark.png)

## 安装与导入资源

1. 重签 IPA 及其嵌套动态库后安装。覆盖更新保持原 Bundle ID，保留资源和存档。
2. 打开一次启动器，创建 `GuestGame` 文件夹。
3. 在“文件”App 中，将游戏目录里的 `archive`、`engine`、`r6` 和 `Cyberpunk2077.app` 完整解压后，直接放入：

   **浏览 → 我的 iPhone / iPad → 赛博朋克2077 → GuestGame**

   如果签名工具修改了应用名称，以实际名称为准。
4. 等待复制完成，回到启动器，选择设备预设和分辨率，再开始游戏。

```text
GuestGame/
├─ archive/Mac/…
├─ engine/…
├─ r6/cache/tweakdb.bin
└─ Cyberpunk2077.app/Contents/…
```

保留全部子目录，不要多套一层 `Cyberpunk 2077`，不要直接放入压缩包。资源约 70 GB（本体）或 96 GB（全部），另留运行空间。IPA 不包含这些大型资源。

## 操作

左半屏空白处按下使用浮动摇杆，右半屏滑动转动视角。支持多点触控和实体手柄。“布局”可调整按键、大小、透明度和镜头灵敏度；约 4 秒无触摸后隐藏按钮。启动页可切换中文和 English。

反馈时请提供机型、完整系统版本、应用版本、分辨率、设备预设和出现问题的场景；日志位于应用文件夹的 `GuestGame` 上一级。

## 构建

仓库目前保留早期公开源码快照；下面的命令用于该快照，不保证重建本次 v8 IPA。本次安装请使用 Release 中的指定文件。

需要 Apple Silicon Mac、Xcode 27 beta / iPhoneOS 27 SDK、Python 3.11+ 和匹配版本的游戏文件。

```sh
cp config.example.json config.local.json
# 在 config.local.json 中设置 game_root 和 developer_dir
python3 tools/build_all.py --platform ios --output dist/Cyberpunk2077-DingElero-universal-v5.ipa
```

## 第三方代码

兼容层参考 [Stray-iOS](https://github.com/xzk49/Stray-iOS)。第三方许可见 [说明文件](THIRD_PARTY_NOTICES.txt)、[Stray-iOS](LICENSE-Stray-iOS.txt)、[curl](curl-COPYING.txt) 和 [OpenSSL](openssl-LICENSE.txt)。
