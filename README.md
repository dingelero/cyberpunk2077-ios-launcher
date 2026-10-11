# DingElero · Cyberpunk 2077 iPhone / iPad Launcher

<img src="App/LauncherAssets/DingElero.png" alt="DingElero logo" width="96" height="96">

**本启动器完全免费。需要自备正版 Cyberpunk 2077 Steam macOS 版游戏文件。**

当前版本 **0.8.1 / build 11**，匹配 **Steam macOS 2.31 ARM64**。可重签 IPA 在本仓库的 **Releases** 中下载。Windows 版、App Store 版及其他版本文件不能直接替换这份构建需要的资源。

## 只有手机：游戏本体放哪里、怎么放

1. 使用你现有的有效签名工具安装 Release 的 IPA，签名包含主应用和全部嵌套动态库。覆盖更新保持实际已安装的 Bundle ID 不变，不要先卸载。
2. **先打开一次启动器**，它会创建 `GuestGame`，启动页显示你实际要使用的文件路径。
3. 在“文件”App 中找到已经取得、完整解压的正版 Steam macOS 2.31 文件。云端文件先完整下载到本机。启动器不下载游戏本体。
4. 打开原始 `Cyberpunk 2077` 文件夹，选中里面的 **archive、engine、r6、Cyberpunk2077.app**，移动或拷贝到：

   **文件 → 浏览 → 我的 iPhone → 赛博朋克2077 → GuestGame**

   iPad 对应“我的 iPad”；如果签名工具改了应用名称，以实际名称为准。
5. 四项直接放在 `GuestGame` 下，保留全部子目录，不要多套一层 `Cyberpunk 2077`。等待复制完成后回到启动器，先选 720p，再开始游戏。

```text
GuestGame/
├─ archive/
│  └─ Mac/…
├─ engine/…
├─ r6/
│  └─ cache/tweakdb.bin
└─ Cyberpunk2077.app/
   └─ Contents/…
```

本体资源约 **70 GB**，全部约 **96 GB**，另留运行与存档空间；解压时压缩包和解压文件同时保留会额外占用空间。IPA 不包含这些大型资源。`GuestGame/Cyberpunk 2077/archive` 或只放一个 ZIP 都不是正确布局。

启动页“使用教程 / How to play”提供离线中英文详细说明，顶部可直接跳到手机放文件步骤。另见 [完整手机教程](docs/DingElero启动器-使用教程.md)。有 Mac 的用户可以选择 Release 附带的 USB 导入工具；手机放文件过程不要求电脑。

## 设备、画面和控制

- 最低系统版本：iOS / iPadOS 18；iPhone 和 iPad 使用同一个 IPA。
- 六组设备预设：iPhone A15/A16、A17 Pro、A18 及以上，iPad A 系列、M1/M2、M3 及以上；支持自动识别或手动选择。
- 各预设都有 **720p / 1080p** 全屏输出选项；输出高度按选择确定，宽度按屏幕比例调整，内部渲染由 MetalFX 动态缩放。
- 左半屏空白处按下生成浮动移动摇杆，松手隐藏；右半屏空白处滑动转视角，没有固定右摇杆。支持多点触控和实体手柄。
- “布局 / Layout”可调整位置、绑定、大小、透明度、显示开关和镜头灵敏度；无手指接触约 4 秒隐藏触控按钮。
- 启动页和触控编辑器可切换中文 / English。游戏字幕与配音语言在游戏里单独设置。

## 验证范围

本版完成了 iOS ARM64 构建、签名结构与 IPA CRC/逐文件 SHA-256 检查，以及 iPhone / iPad 模拟器中的 Logo、双语教程、目录创建、路径显示、跳转、滚动和返回检查。

游戏本体、19 个游戏/兼容层动态库和性能配置与上一版 universal-v5 一致。模拟器探针没有加载商业游戏；**本次发布不代表所有设备已达到持续 30 分钟稳定 30 FPS，也不代表所有设备的 HDR 或手机大文件移动均已实测**。预设以 30 FPS 为目标，真实兼容性与持续性能请在对应设备测试。

遇到问题请记录机型、系统、预设、输出和具体场景。日志在“文件”App 的应用文件夹根目录（`GuestGame` 上一级）：长按 `probe-report.json` 或 `performance-*.jsonl`，点“共享”。提交公开问题前自行移除不希望公开的个人信息。

## 从自己拥有的游戏文件构建

需要 Apple Silicon Mac、Xcode 27 beta / iPhoneOS 27 SDK、Python 3.11 或更新版本，以及匹配版本的正版 Steam macOS 游戏文件。

```sh
cp config.example.json config.local.json
# 编辑 config.local.json 的 game_root 与 developer_dir
python3 tools/build_all.py --platform ios --output dist/Cyberpunk2077-DingElero-universal-v5.ipa
```

构建工具会检查原始游戏版本/UUID/哈希，并下载固定版本的 curl/OpenSSL 源码。`config.local.json`、原始商业游戏、构建产物、私人存档和设备原始日志不提交到 Git。

界面组件探针：`python3 tools/build_universal_probe.py`。安装到模拟器后用 `--qa-branding` 运行；该探针独立于商业游戏。

## 致谢与第三方许可

启动器署名与个人 Logo：**DingElero**。兼容层参考 [xzk49/Stray-iOS](https://github.com/xzk49/Stray-iOS)，固定提交 `af325c2ced6c7b4da51c5b2be05d5147e8d37007`；保留其 MIT 许可。curl / OpenSSL 的许可也随源码和 IPA 保留。

见 [第三方说明](THIRD_PARTY_NOTICES.txt)、[Stray-iOS 许可](LICENSE-Stray-iOS.txt)、[curl 许可](curl-COPYING.txt)、[OpenSSL 许可](openssl-LICENSE.txt)。第三方兼容层许可不涵盖商业游戏的可执行代码和资源。

## English quick start

**Completely free launcher by DingElero. Bring your own legitimate Cyberpunk 2077 Steam macOS 2.31 ARM64 files.**

Download the IPA from Releases and re-sign the app and embedded libraries with your existing valid signing workflow. Keep the same Bundle ID for updates. Open the launcher once to create `GuestGame`.

On your phone, move the fully extracted `archive`, `engine`, `r6` and `Cyberpunk2077.app` directly into **Files → Browse → On My iPhone / iPad → the installed app name → GuestGame**. Preserve their subfolders, with no extra Cyberpunk 2077 folder level. Allow about 70 GB for the base game or 96 GB for all resources plus runtime space. These file-placement steps do not require a computer; the launcher does not supply the game files.

Choose English and start at 720p. How to play opens the offline guide. Use a controller or the floating left stick / free right-side camera gestures; Layout edits controls. Sustained performance, compatibility and HDR require physical-device testing.
