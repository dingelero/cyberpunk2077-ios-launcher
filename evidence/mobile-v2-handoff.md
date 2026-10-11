# 移动端优化 v2：安装、测试及回退

交付版本 **0.5.0 / build 7，iphone16-mobile-v2**，目标 iPhone 16 Pro Max。提供可自行重签的完整小 IPA，以及针对旧 IPA 的游戏本体差分补丁。约 96 GB 正版资源继续使用已导入的应用数据。

**尚未验证连续 30 分钟稳定 30 FPS、实机触控和 HDR 输出。** 已完成 ARM64 指令和设置迁移测试、兼容层组件回归、触控模拟器测试、iOS 构建和交付包校验；模拟器触控测试没有加载商业游戏。上一版 v1 的实机反馈没有改善，因此不再推荐该流送并发方案。本版也不能凭构建成功承诺不卡顿。

## 本版具体改动

- 修改游戏本体原生 `CAMetalDisplayLink` 的请求：在 VSync Off 分支，将使用屏幕原生刷新率的指令替换为请求 30 Hz。游戏菜单的 30 FPS 上限与该显示回调原先是两套设置。只修改这一条显示频率指令；VSync On 分支、回调方法、画面提交方式、AI、物理和游戏 tick 没有改动。已执行抽取后的 ARM64 指令验证 1–240 Hz 输入；实际设备回调频率、发热和性能收益尚未验证。
- 撤销 v1 的流送并发与解压缓冲更改，恢复游戏默认 2 个常规加载线程、2 个大量加载时保留名额、1 MiB 专用解压缓冲。此前减少桌面内存预留、路径转换缓存、主线程窗口更新合并和 Metal 回调减负仍保留。没有删除 NPC、任务、地形、粒子、纹理、车辆或其他玩法内容，也未缩短流送距离。
- 首次启动进行一次设置迁移：全屏输出画布短边 720、FPS 上限 30、原生 MetalFX 动态缩放、动态分辨率目标 30、缩放范围 40–50%，默认关闭两项帧生成。游戏里的帧生成选项仍保留，之后用户改动不会被每次启动覆盖。现有手机设置的其余 302 项选项通过迁移测试保持原值；HDR、质量和人群设置保持原值。
- **720p 指输出画布，当前设置经过升频，不是内部原生 720p。** iPhone 16 Pro Max 的全屏画布约 1564×720；40–50% 的缩放设置意味着内部像素更少。关闭帧生成后应按真实呈现帧间隔判断流畅度。
- 新增触摸移动/视角摇杆、ABXY、肩键和扳机，走原生 `GCVirtualController` 手柄输入。菜单、地图、物品、扫描、冲刺和方向快捷键走现有键盘事件接口。无触摸 4 秒后控件隐藏，触摸重新显示，持续按住不会被隐藏；界面没有每帧轮询。实体手柄优先的实现保留，但真机连接切换与完整游戏响应仍待测试。未新增鼠标模拟。
- 普通启动每 5 秒保存一次呈现间隔、进程 CPU、内存和 iOS 热状态，按 PID/启动时间区分测试轮次；后台暂停采样。每轮上限 10 MiB，保留最近 6 轮。普通启动不采集逐线程 CPU，避免诊断本身增加较多开销。GPU 时长只取原本就有的呈现完成回调，并不等于整帧 GPU 占用率。

本版仍为 ARM64 原生执行和 Metal 渲染，不使用 JIT、CPU 模拟或串流。没有把 SDK 查询结果伪造为更强的 GPU，也没有强制重写实际热状态。HDR 通路和游戏选项保留；实际 HDR 画面尚未验证。iPhone 13 Pro 没有达标验证。

## 安装完整 IPA

1. 保存进度并退出游戏。使用 `Cyberpunk2077-iPhone16ProMax-mobile-v2-candidate.ipa`。
2. 在现有 iLoader 中使用同一 Apple ID 重签，覆盖同一应用。签名后的 ID 应继续为 `local.cyberpunk.ios.rebuilt.<your-signing-suffix>`。**不要卸载旧应用或创建新的应用 ID**，以便保留已导入资源和存档。
3. 重签主应用及嵌套库；安装后确认版本为 0.5.0 / build 7。首次启动会保存完整设置备份，再应用本版一次性显示设置。若安装失败，保留原应用并收集 iLoader 的错误，不要删除应用数据。
4. 使用现有存档进入游戏。确认 VSync 为 Off，让修改后的 30 Hz 分支生效；本次迁移不重写 VSync 选项。保留 30 FPS 上限、关闭帧生成和动态 MetalFX 设置，先完成对照。原先已经较低的画质项目没有再次强制降低。

IPA 声明了 iOS 游戏分类和 Game Mode 支持；是否由系统实际启用须在手机确认，包校验不能证明已进入游戏模式。

## 可选：从旧 IPA 生成补丁版

完整 IPA 已包含本次修改，不需要再打补丁。独立 ZIP 用于复现游戏本体差分和回退，包含指令配方、源码差异及离线应用工具，不含完整商业游戏可执行文件或资源。

支持两个**原始、未重签**的旧交付包：

| 输入 IPA | 必须匹配的 SHA-256 |
| --- | --- |
| `Cyberpunk2077-iPhone16ProMax-game-streaming-v1-candidate.ipa` | `82e03db33177a928c00807bf13fee150e22aa8768bdbb73bb7e4e173914a4377` |
| `Cyberpunk2077-iPhone16ProMax-efficiency-v4-candidate.ipa` | `2ff1c3287001f8414f229d3b6c5fdcde19385f59a1448854a0adf8fd5dfdd658` |

将其中一个旧 IPA 放在解压后的补丁文件夹旁，双击 `生成优化版IPA.command`，得到 `mobile-v2-patched.ipa` 后自行重签。原文件不被修改；重签过的旧 IPA 不匹配补丁基线。工具验证每个输出文件的 SHA-256，错误输入和损坏的补丁会拒绝生成。不要将补丁脚本直接作用于手机资源或原始 Steam 文件。

## 你进行半小时实机测试

从同一存档、同一路线测试，覆盖走路、转视角、驾驶和战斗。分别记录前 5 分钟、15 分钟和 30 分钟的体验，尤其注意热起来后是否仍掉到约 15 FPS。整轮保持画质和帧生成设置不变；记录是否充电、低电量模式及 HDR 状态，便于对照。触控可先断开实体手柄验证，然后重新连接检查手柄功能。

测试后保存并关闭游戏，USB 连接、解锁手机，双击本机 `outputs/读取移动端性能记录.command`。工具只读取已有文件，不会关闭、启动、更新游戏或重新校验 96 GB 资源。完整记录和 `performance-summary.json` 保存到工程的 `work/device-startup/mobile-v2-日期时间/`，终端会显示路径。若闪退，直接保留记录；不要反复重新启动覆盖最新轮次。

原始记录保留在应用 `Documents/performance-PID.jsonl`。`thermalState` 的 0/1/2/3 对应 nominal/fair/serious/critical。呈现统计含菜单和加载，滚动窗口重叠；平均 FPS 不能独立证明战斗流畅，也不能自动验收 30 分钟。最差帧间隔、P95、持续前台采样长度及热状态应一起看。日志中的初始显示设置也不能证明玩家后来没有更改选项。

## 回退

使用已有 `Cyberpunk2077-iPhone16ProMax-efficiency-v4-candidate.ipa`，同一 Apple ID、同一应用 ID 覆盖安装。资源和存档继续沿用；v1 已反馈无明显改善，不建议作为默认回退目标。

首次迁移前的设置备份位于应用数据容器：

`Library/Application Support/CD Projekt Red/Cyberpunk 2077/UserSettings-before-iphone16-mobile-v2.json`

如需完全恢复设置，在游戏关闭时先备份当前 `UserSettings.json`，再用上述备份替换同目录的 `UserSettings.json`。旧版也有自己的迁移标记；不要通过卸载应用来回退。原始 Steam 游戏文件未被本次构建修改。

## 网络依据与边界

- [Apple 的 Cyberpunk 原生移植分享](https://developer.apple.com/videos/play/wwdc2026/356/)讨论原生性能分析、MetalFX 和动态分辨率；桌面结果不能当作 iPhone 已达标证据。
- [AMD FSR 3 文档](https://gpuopen.com/fidelityfx-super-resolution-3/)建议插帧前具备较高基础帧率。当前实机基础帧率偏低，因此本版默认关闭帧生成，再判断真实长帧。
- [Potato mod 作者页面](https://www.nexusmods.com/cyberpunk2077/mods/11878)的极低配方案依赖 Windows CET 和效果开关；直接关闭升频、光照或内容不能满足这里保留功能的要求，未打包该模组文件。
- [OAI tweaks 作者页面](https://www.nexusmods.com/cyberpunk2077/mods/23257)不是 iPhone 原生补丁的已验证依据，未照搬未经验证的线程和预算参数。
- [流送 bug workaround 作者页面](https://www.nexusmods.com/cyberpunk2077/mods/22857)依赖 CET，强制卸载世界节点的诊断方法没有放进本版正常玩法。

本版组件证据见 `mobile-v2-components.json` 和 `mobile-v2-touch-simulator.json`。旧版帧率和热状态不能作为本版改善证据；正式验收仍是你在 iPhone 16 Pro Max 上的 30 分钟连续实际玩法。
