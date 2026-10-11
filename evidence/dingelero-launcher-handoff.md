# DingElero 免费启动器 · 0.8.1 / build 11

本启动器完全免费，需要自备正版 **Cyberpunk 2077 Steam macOS 版游戏文件**。当前构建匹配 **2.31 ARM64**；Windows 版及其他版本不可直接代替。IPA 不包含大型游戏资源。

启动页加入 DingElero 署名及用户提供的个人像素 Logo。Logo 保持原图、采用最近邻缩放，搭配黄、青色界面。点“使用教程 / How to play”打开离线教程，顶部直接显示手机文件路径，并提供“手机放游戏文件”按钮跳到具体步骤；启动页语言切换同时作用于署名说明、教程及触控界面。游戏字幕和配音在游戏里单独选择。

## 安装与更新

1. 按你现有签名工具的有效签名安装流程安装 IPA，签名须包含主应用和全部嵌套动态库；最低系统版本为 iOS / iPadOS 18。本教程的手机放文件步骤从 IPA 已安装开始。
2. 覆盖更新保持已安装应用的 Bundle ID 不变。沿用签名工具实际已安装的 ID；不要先卸载，以保留资源、存档和自定义触控。每位测试者使用自己当前安装的 ID。
3. 新设备需自行导入同版本正版资源；本体约 70 GB、全部约 96 GB，另留存档与运行空间。资源不在 IPA 内，也不会从其他设备自动复制。

## 只有手机：游戏本体放在哪里

**文件 → 浏览 → 我的 iPhone → 赛博朋克2077 → GuestGame**

iPad 对应“我的 iPad”；如果签名时改了应用名称，就打开实际安装名称的文件夹。这里的应用文件夹就是应用的 Documents，GuestGame 已在新版启动器首次打开时自动创建，不需要越狱或访问系统路径。

1. 安装后先打开一次启动器，再切到“文件”App。启动页也会显示你的设备上实际应该使用的路径。
2. 把你已经取得的正版 **Steam macOS 2.31 ARM64** 游戏文件存到“文件”App。例如下载自己的网盘备份后选“存储到文件”，或从连接手机的存储设备复制。云端文件先完整下载到本机。本教程以你已取得匹配版本文件为前提，启动器不下载游戏本体。
3. 如果收到 ZIP，点击解压。RAR、7z 或分卷包用支持其格式的工具完整解压；压缩包与解压后的文件同时保留会占用额外空间。不要把 ZIP 或 IPA 本身放进去当作游戏资源。
4. 打开解压后的 `Cyberpunk 2077` 文件夹，右上角“…”→“选择”，选中其中的 **archive、engine、r6、Cyberpunk2077.app** 四项。点“移动”，依次选择“我的 iPhone → 赛博朋克2077 → GuestGame”，确认移动；提供方只显示“拷贝 / 粘贴”时使用该操作。
5. 四项必须直接位于 GuestGame 下，所有子文件和目录保持原样。不要多套一层 `Cyberpunk 2077`。等全部文件移动或复制完成，再回启动器选 720p 并开始游戏。

正确结构：

```text
我的 iPhone / 赛博朋克2077 / GuestGame /
├─ archive /
│  └─ Mac / ...
├─ engine / ...
├─ r6 /
│  └─ cache / tweakdb.bin
└─ Cyberpunk2077.app /
   └─ Contents / ...
```

错误结构：`GuestGame/Cyberpunk 2077/archive`、`GuestGame/GuestGame/archive`，或只放入一个 ZIP。Windows 的 `archive/pc` 不能代替 macOS 的 `archive/Mac`。

找不到应用文件夹时，先打开一次新版启动器，再回“文件 → 浏览 → 我的 iPhone / iPad”刷新。缺少资源时先查层级、版本和解压是否完整；启动器关键文件预检不代表全部资源已经做过哈希核验。本轮只验证了模拟器中的目录创建与指南路径，没有执行真机的约 96 GB 文件移动。

文件移动、解压操作依据 [Apple 文件整理指南](https://support.apple.com/zh-cn/guide/iphone/iphab82e0798/ios)；应用目录开放使用 [Apple 文档共享规则](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html)。

## 可选：有 Mac 时使用 USB 导入

将交付包内的 `导入正版游戏资源.command` 和 `Cyberpunk2077-iOS-rebuild-source.zip` 放在同一个文件夹。Mac 需要 Python 3.11 或更新版本；工具首次运行会下载固定依赖。

用 USB 只连接一台目标 iPhone / iPad，解锁并信任电脑。关闭游戏，双击导入工具。默认读取本机 Steam 的 `Cyberpunk 2077` 文件夹；未找到时按提示选择自己的目录。回车选择本体，输入 `all` 选择全部资源。

等待工具报告成功。工具会核对传输后的文件 SHA-256；中断后重新运行可验证断点并续传。每台新设备单独导入。新版工具预检识别 iPhone 与 iPad，但本轮没有连接真机执行导入。

## 设备选项与操作

打开启动器，默认自动识别设备，也可按芯片手动选择六种预设之一。新设备先选择 720p，点“开始游戏”保存并启动；需要时再对照 1080p。

720p / 1080p 是全屏输出高度，宽度按设备比例取偶数，内部渲染由 MetalFX 动态缩放。所有预设目标 30 FPS；各设备持续帧率、发热及 HDR 输出以真机测试为准。

实体手柄可直接使用。触控游玩时，左半屏空白处按下生成浮动移动摇杆，松手立即隐藏；右半屏空白处滑动转动镜头，无固定右摇杆。可同时移动、转视角、瞄准和射击。显示“自动 / 游玩 / 界面”的输入模式按钮可循环切换模式；菜单操作使用界面模式。

点“布局”可移动按钮，调整绑定、大小、透明度、显示开关及镜头灵敏度；点“保存完成”保存。无手指接触约 4 秒后触控按钮隐藏，再触摸屏幕唤回。启动页“触控 / 界面”与编辑器的语言按钮均可切换中文 / English。

手机上即可分享日志：在“文件”App 打开“我的 iPhone / iPad → 赛博朋克2077”根目录（GuestGame 上一级），长按 `probe-report.json` 或 `performance-*.jsonl`，点“共享”。存档位于应用自己的可写存储中，同 ID 覆盖更新保留；不要通过卸载清理游戏。

如有 Mac，日志也可通过交付包的 `读取移动端性能记录.command` 导出；它与源码 ZIP 放在同一文件夹，Mac 需安装包含 `devicectl` 的 Xcode。该工具只读取已保存记录，不启动、关闭或更新游戏，导出目录为交付文件夹上级的 `work/launcher-logs`。

## 本次更新与验证范围

本次更新启动器展示、手机优先教程，以及启动页自动创建 GuestGame 的行为。保留 universal-v5 的性能预设、游戏本体与兼容层动态库、触控逻辑及配置迁移标记。没有因署名更新重置画质、HDR、分辨率、设备选项或键位。

构建、签名结构、IPA 内容与模拟器界面检查的结果见随包的校验文件。本轮模拟器检查仅覆盖启动器 Logo、署名、双语说明、GuestGame 创建、文件路径、教程滚动和返回；没有加载商业游戏，也没有执行手机安装、游戏性能测试或 VPN 操作。

## English quick start

**DingElero's launcher is completely free. Bring your own legitimately owned Cyberpunk 2077 Steam macOS 2.31 ARM64 files. Large game resources are imported separately.**

1. Install the IPA with your existing valid signing workflow, including all embedded libraries. iOS / iPadOS 18 or later is required. Keep the same Bundle ID for updates. Open the launcher once to create GuestGame.
2. On your phone, obtain your matching legitimate macOS game files from your own backup or connected storage and extract them fully. In Files, select `archive`, `engine`, `r6` and `Cyberpunk2077.app` inside the extracted Cyberpunk 2077 folder. Move or copy them to **Files → Browse → On My iPhone / iPad → 赛博朋克2077 → GuestGame** (use the installed app's actual name). These four items must be directly inside GuestGame, without another Cyberpunk 2077 folder layer. Preserve all subfolders and wait for the transfer to finish. These placement steps do not require a computer; the launcher does not download the game. File operations follow [Apple's Files guide](https://support.apple.com/guide/iphone/organize-files-and-folders-iphab82e0798/ios).
3. Select English in the launcher. Use automatic detection or a chip preset, start at 720p, and tap Start game. Tap How to play for the complete offline guide. 720p / 1080p is output height; MetalFX scales internal rendering. Sustained performance requires device testing.
4. Use a physical controller or touch. Hold empty space on the left for a floating movement stick; swipe empty space on the right to look. The Auto / Play / UI button cycles input modes. Layout lets you edit controls and look sensitivity; choose Save / Done. Touch buttons hide after about four seconds without fingers on screen. Game text and voice language are configured in the game.
5. Share `probe-report.json` or `performance-*.jsonl` from the app's folder in Files (the parent of GuestGame). A Mac is optional: use the supplied import command with `Cyberpunk2077-iOS-rebuild-source.zip` alongside it for USB import; Python 3.11 or later is required. The optional read-only log command also requires Xcode with `devicectl`.
