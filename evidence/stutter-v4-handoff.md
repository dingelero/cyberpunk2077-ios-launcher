# 卡顿优化候选版 stutter-v4：安装与对照测试

版本 **0.7.0 / build 9**；完整包 `Cyberpunk2077-iPhone16ProMax-stutter-v4-candidate.ipa`。本版已构建和校验，但还没有实机性能结果。目标仍是 iPhone 16 Pro Max 的全屏 720p 输出、30 FPS 连续游玩 30 分钟；目前不能宣布达标。720p 为升频后的输出，内部使用原生 MetalFX 动态分辨率。

## 安装

用现有 iLoader / Apple ID 重签主应用及所有嵌套动态库，沿用当前应用 ID `local.cyberpunk.ios.rebuilt.<your-signing-suffix>` 覆盖更新。**不要卸载旧应用**，应用中的正版资源、存档与 touch-v3 键位布局继续使用。完整 IPA 已包含本次补丁，无须重新导入约 96 GB 游戏文件或再叠加 ZIP 补丁。

第一次启动会备份完整设置为 `Library/Application Support/CD Projekt Red/Cyberpunk 2077/UserSettings-before-iphone16-stutter-v4.json`，然后迁移一次帧调度和存储模式设置。后续启动保留你的改动。HDR、所有画质选项和游戏玩法数据保留，帧生成选项仍在，但本版首次迁移关闭帧生成。

## 实际改动

1. 游戏原有 `Streaming / MaxNodesPerFrame` 的每帧场景节点处理预算从 300 改为 192，意图降低资源集中附加的 CPU 尖峰。保留加载屏幕的 999999 预算、原有流送距离与节点处理代码；没有删除人物、车辆、任务、地图、战斗、物理或粒子系统。**这属于实验性的批次调整，可能让高速移动时的场景出现得更慢，需要检查地形、碰撞和物件加载。**
2. 关闭游戏独立的“最高帧率”限帧器，使用已存在的原生 30 Hz `CAMetalDisplayLink` 及游戏自己的 drawable / semaphore 循环。游戏设置里最高帧率开关显示关闭是预期行为；不应把这个开关再打开来测试本版。
3. `HDDMode` 从 Auto 改为 Off，明确选择 SSD 存储模式；保留原生缓存容量、流送线程数量和解压缓冲区，未采用桌面大内存的缓存膨胀方案。
4. 普通游玩不再每 5 秒在 UIKit 主线程生成完整诊断。简要帧时间、内存、热状态、引擎实际节点预算在后台每 5 秒记录，保留卡顿尖峰，不使用伪造 FPS 或删掉长帧的算法。

游戏本体的 ARM64 指令与 touch-v3 包相同；本次修改的游戏文件是宿主重定向给原游戏读取的 `engine/config/platform/mac/rendering.ini`，仅追加 `[Streaming] MaxNodesPerFrame=192`。原始 Steam 安装和已导入的大型 archive 不被写入。触控 v3、HDR 接口、全屏、存档与实体手柄代码沿用上一版。

## 已检查与待验证

已检查：当前游戏 UUID / 指令哈希；原生参数注册的类别、整数范围与实际消费者；240 种面板刷新率下的 ARM 指令结果；设置迁移、幂等性、其他 300 个设置保持；配置未加载时诊断不会标记生效；iOS ARM64 构建、代码签名结构、动态链接依赖、IPA CRC 及每个文件的 SHA-256。

**未验证：** 当前手机上的配置是否生效、场景加载延迟、卡顿是否减少、发热和内存是否改善、连续 30 分钟稳定 30 FPS、真机 HDR 输出。手机当前不可读取，未自动安装、启动、关闭游戏或更改 VPN。触控组件的历史检查不等于商业游戏内全部触控已验证。

## 网络参考

- [OAI Tweaks 掌机方案](https://www.nexusmods.com/cyberpunk2077/mods/23257?tab=files)：作者提供针对共享显存掌机的版本，方向包括帧时间、流送和 CPU 批次。其 Windows 配置值没有直接照搬；本版只使用当前 macOS ARM64 二进制中能找到消费者的参数。
- [Apple 原生帧调度说明](https://github.com/apple/game-porting-toolkit/blob/main/game-porting-skills/skills/presenting-metal-drawables/references/frame-pacing.md)：使用原有显示循环和目标呈现时间，避免随意替换引擎同步机制。
- [CDPR 的 Mac 移植报告](https://developer.apple.com/videos/play/wwdc2026/356/)：原生 MetalFX、动态分辨率与硬件性能预算；这不是 iPhone 实测。
- [Choom Memory Booster 作者说明](https://www.nexusmods.com/cyberpunk2077/mods/31975?tab=description)：它只清理 CET Lua 堆，不管理游戏的系统内存或 GPU 资源，因此未引入这个 Windows/CET 模组。

这些网页提供思路，并不能证明本版能消除 iPhone 卡顿。旧实机记录曾出现约 6.3 GB 进程占用、约 3 GB 压缩内存及严重热状态；它们来自更早版本，不能当成本版的结果或已确定根因。

## 你来测试

用手柄加载同一存档，先在常卡顿的位置走路、转视角、驾驶和战斗，再连续玩到第 30 分钟。第一轮保留本版首次启动后的帧调度设置，记录第 1 / 5 / 15 / 30 分钟的体验，特别留意场景加载、地形、物件或碰撞异常。若复现问题，不需要重复安装或重新导入资源。

应用的 Documents 中保留 `performance-进程号.jsonl`、`memory-report.json`、`probe-report.json`。连接手机后可双击现有 `读取移动端性能记录.command` 脚本或从文件共享导出；也可在项目里运行 `python3 tools/collect_mobile_trace.py`。JSONL 的 `engine.nodeBudgetApplicationVerified` 会指示实际原生值是否为 192，并验证加载预算仍为 999999；为 false 时不能宣称该游戏配置已经生效。

## 补丁与回退

完整 IPA 是直接安装用包。`Cyberpunk2077-iPhone16ProMax-stutter-v4-patch.zip` 是离线差分补丁，适用于保留的原始 touch-v3 或 mobile-v2 候选 IPA，不适用于重签后的 IPA。解压后双击“生成优化版IPA.command”，生成的新 IPA 再重签；它不会自动安装或修改手机数据。补丁包含本次宿主修改及游戏配置修改，未包含完整商业游戏可执行文件。

若变差，用同一 ID 覆盖安装保留的 touch-v3 或 mobile-v2 IPA。旧版本首次启动会按自己的迁移标记重新应用原先的帧调度设置；游戏节点预算恢复到旧版原生配置。资源和存档继续使用。若需要完整恢复手动画质设置，可保留本版的启动前设置备份。
