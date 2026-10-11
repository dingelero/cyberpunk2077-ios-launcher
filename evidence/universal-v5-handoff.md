# iPhone / iPad 通用测试版：0.8.0 / build 10

安装文件：Cyberpunk2077-iPhone-iPad-universal-v5.ipa。一个 IPA 同时支持 iPhone / iPad 安装，六组设备预设各自提供 720p / 1080p 全屏输出。

## 安装与选择

1. 用 iLoader / Apple ID 重签主应用及所有嵌套动态库。原手机沿用 local.cyberpunk.ios.rebuilt.<your-signing-suffix> 覆盖更新，不要卸载；已有正版资源、存档和自定义键位继续使用。
2. 打开应用，在启动页选择设备预设、720p / 1080p，再点“开始游戏”；点开始后保存选择。默认自动识别 + 720p。未知 GPU 使用保守预设，也可以手动选择。
3. 启动页“触控 / 界面”可切换中文 / English；游戏内点“布局 / Layout”，面板标题旁也可即时切换。语言独立保存，取消或重置键位不会重置语言。游戏自身的字幕、配音语言继续在游戏设置里选择。
4. 新设备需单独导入自己拥有的同版本正版资源：使用现有“导入正版游戏资源.command”，一次只连接一台待导入设备。完整资源约 96 GB、本体约 70 GB；IPA 不含大型资源。

## 预设

| 预设 | 对应系列 | 内部动态渲染比例 | 输出 |
| --- | --- | --- | --- |
| iPhone A15 / A16 | iPhone 13、14 系列，15 / Plus | 50–50% | 720p / 1080p |
| iPhone A17 Pro | 15 Pro / Pro Max | 40–50% | 720p / 1080p |
| iPhone A18 及以上 | 16 系列及更新芯片 | 40–50% | 720p / 1080p |
| iPad A 系列 | iPad / mini | 50–50% | 720p / 1080p |
| iPad M1 / M2 | 对应芯片的 Air / Pro | 40–60% | 720p / 1080p |
| iPad M3 及以上 | 对应芯片的 Air / Pro，包括 M4、M5 | 40–67% | 720p / 1080p |

百分比按输出的每个轴计算；实际下限由原生 MetalFX 能力收紧，无法可靠查询时用 50%。所有预设目标 30 FPS；这些是测试配置，尤其旧 iPhone 与小内存设备的实际兼容性、持续帧率仍待验证。

720p / 1080p 指全屏输出高度，宽度按设备比例取偶数，内部由 MetalFX 动态缩放。16 Pro Max 输出为 1564×720 / 2346×1080；11 英寸 M4 iPad Pro 为 1044×720 / 1566×1080；4:3 iPad 为 960×720 / 1440×1080。1080p 像素数约为对应 720p 的 2.25 倍，先测 720p 再对照。

首次使用本版或改变预设、输出尺寸时应用一次配置，其后保留游戏内调整。首次迁移备份位于 Library/Application Support/CD Projekt Red/Cyberpunk 2077/UserSettings-before-universal-v5.json。新装设备从匹配游戏的原始 schema 生成必要覆盖设置，其他设置使用游戏默认值。

## 保留及验证范围

沿用 stutter-v4 的游戏本体指令、每帧节点预算 192、原生 30 Hz 显示循环、SSD 模式、后台简要日志和默认关闭帧生成的策略。已有画质、玩法、HDR、手柄和自定义键位设置保留，帧生成选项仍可选择。打包后的商业游戏动态库与 stutter-v4 逐字节相同。iPad 默认触控按钮放大。

已完成 iOS ARM64 构建、签名结构、链接依赖、IPA CRC 和逐文件 SHA-256 检查；72 组配置 / 分辨率 / 屏幕比例组件检查、八种触控布局检查、24 项绑定双语文本检查；模拟器中的语言切换、显示模式、配置幂等性和自定义按钮大小保留检查。模拟器探针没有加载商业游戏。

尚无不同设备连续 30 分钟稳定 30 FPS 的实测结论。请你们验证真实启动、渲染、HDR、多指 / 手柄、场景流送、温度和持续帧率。

每台设备用相同存档测试走路、驾驶、转视角和战斗，记录第 1 / 5 / 15 / 30 分钟的表现，以及机型、系统、预设和输出。Documents 中 performance-进程号.jsonl、probe-report.json、memory-report.json 可用现有“读取移动端性能记录.command”导出。需要回退时，保持 ID 不变，覆盖安装保留的 stutter-v4 IPA；资源和存档继续使用，上一版迁移标记会恢复其配置。

## 规格参考

分组参考 Apple 的 [iPhone 13 Pro 规格](https://support.apple.com/en-ie/111871)、[iPhone 16 Pro 规格](https://support.apple.com/en-nz/121031)、[M4 iPad Pro 规格](https://support.apple.com/en-gb/119892)、[M4 iPad Air 公告](https://www.apple.com/newsroom/2026/03/apple-introduces-the-new-ipad-air-powered-by-m4/)及 [M5 iPad Pro 规格](https://support.apple.com/en-ie/125407)。规格不代表移植性能；自动选择查询设备实际报告的原生 Metal GPU 名称。
