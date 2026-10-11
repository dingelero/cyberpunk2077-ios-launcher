#import "LaunchGuide.h"
#import "compat/UILanguage.h"

NSString *CPGameFilesPath(void){return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/GuestGame"];}
NSString *CPGameFilesLocation(void){
    NSString *device=UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad?CPUIString(@"我的 iPad",@"On My iPad"):CPUIString(@"我的 iPhone",@"On My iPhone");
    NSString *app=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"赛博朋克2077";
    return [NSString stringWithFormat:CPUIString(@"文件 → 浏览 → %@ → %@ → GuestGame",@"Files → Browse → %@ → %@ → GuestGame"),device,app];
}

static UIColor *CPGuideCyan(void){return [UIColor colorWithRed:0.25 green:0.91 blue:0.98 alpha:1];}
static UIColor *CPGuideYellow(void){return [UIColor colorWithRed:0.99 green:0.88 blue:0.11 alpha:1];}
static UILabel *CPGuideLabel(NSString *text,CGFloat size,BOOL heading){
    UILabel *label=[UILabel new];label.text=text;label.numberOfLines=0;
    label.font=[UIFont systemFontOfSize:size weight:heading?UIFontWeightSemibold:UIFontWeightRegular];
    label.textColor=heading?CPGuideYellow():[UIColor colorWithRed:0.78 green:0.86 blue:0.90 alpha:1];
    return label;
}
@interface CPLaunchGuide ()
@property(nonatomic,strong) UIScrollView *guideScroll;
@property(nonatomic,strong) UIView *phoneSection;
@end
@implementation CPLaunchGuide
- (BOOL)prefersStatusBarHidden{return YES;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskLandscape;}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=CPUIString(@"使用教程",@"How to play");
    self.view.backgroundColor=[UIColor colorWithRed:0.018 green:0.032 blue:0.043 alpha:1];
    self.view.accessibilityIdentifier=@"launch-guide";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:CPUIString(@"返回启动器",@"Back to launcher") style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier=@"close-launch-guide";
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    self.guideScroll=scroll;
    scroll.accessibilityIdentifier=@"launch-guide-scroll";scroll.indicatorStyle=UIScrollViewIndicatorStyleWhite;[self.view addSubview:scroll];
    UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=20;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *width=[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40];width.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [stack.centerXAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.centerXAnchor],[stack.widthAnchor constraintLessThanOrEqualToConstant:720],width,
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:20],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24]]];
    UILabel *intro=CPGuideLabel(CPUIString(@"DingElero // 免费启动器\n请自备正版 Cyberpunk 2077 Steam macOS 版游戏文件。IPA 不包含大型游戏资源。",@"DingElero // FREE LAUNCHER\nBring your own legitimately owned Cyberpunk 2077 Steam macOS game files. Large game resources are imported separately."),15,YES);
    intro.accessibilityIdentifier=@"guide-requirements";[stack addArrangedSubview:intro];
    UILabel *destination=CPGuideLabel(CPGameFilesLocation(),13,NO);destination.textColor=CPGuideCyan();destination.accessibilityIdentifier=@"guide-files-location";[stack addArrangedSubview:destination];
    UIButton *jump=[UIButton buttonWithType:UIButtonTypeSystem];[jump setTitle:CPUIString(@"手机放游戏文件：直接查看步骤 ↓",@"Phone file placement: jump to steps ↓") forState:UIControlStateNormal];
    [jump setTitleColor:CPGuideYellow() forState:UIControlStateNormal];jump.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    jump.layer.borderWidth=1;jump.layer.borderColor=[CPGuideCyan() colorWithAlphaComponent:0.7].CGColor;jump.layer.cornerRadius=4;
    [jump.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;jump.accessibilityIdentifier=@"jump-to-phone-import";
    [jump addTarget:self action:@selector(showPhoneSteps) forControlEvents:UIControlEventTouchUpInside];[stack addArrangedSubview:jump];
    NSString *phoneImport=[NSString stringWithFormat:CPUIString(@"1. 安装后先打开一次启动器，它会自动建立 GuestGame 文件夹。游戏文件的最终位置是：\n%@\n\n2. 在“文件”App 找到你已经取得的正版 Steam macOS 2.31 游戏文件，例如从个人备份下载并“存储到文件”，或从手机连接的存储设备复制。ZIP 点一下解压；其他格式或分卷包需用支持该格式的工具完整解压。先确保所有文件已下载到本机。\n\n3. 打开解压后的 Cyberpunk 2077 文件夹，点右上角“…”→“选择”，选中里面的 archive、engine、r6、Cyberpunk2077.app 四项，点“移动”，选择上面的 GuestGame，再确认移动。有些文件提供方显示“拷贝 / 粘贴”，也可以使用。\n\n4. 这四项必须直接放在 GuestGame 里面，保留其下全部子文件夹和文件；不要再套一层 Cyberpunk 2077。等待全部移动或复制完成后，回启动器选择 720p 并开始。不要把 IPA、ZIP、RAR 或 7z 压缩包直接当作游戏资源。\n\n只有手机也可完成以上放文件步骤；前提是你已取得匹配版本的正版文件，启动器不会下载游戏。",@"1. Open the launcher once after installation; it creates GuestGame automatically. The final destination is:\n%@\n\n2. In Files, locate your already obtained, legitimate Steam macOS 2.31 game files, such as your downloaded personal backup saved to Files or files copied from connected storage. Tap a ZIP to extract it; other formats or split archives need a compatible extraction tool. Download all cloud files to the device first.\n\n3. Open the extracted Cyberpunk 2077 folder. Tap … → Select, select archive, engine, r6 and Cyberpunk2077.app, then choose Move and the GuestGame destination above. Copy and Paste can also be used if offered by the file provider.\n\n4. Put these four items directly inside GuestGame and preserve all their subfolders and files. Do not add another Cyberpunk 2077 folder level. Wait for the entire move or copy to finish, then return to the launcher and start at 720p. IPA and compressed ZIP/RAR/7z files are not game resources.\n\nThese file-placement steps need only your phone. You must already have the matching legitimate files; the launcher does not download the game."),CPGameFilesLocation()];
    NSArray *sections=@[
        @[CPUIString(@"01 / 准备游戏与设备",@"01 / Prepare your game and device"),
          CPUIString(@"当前版本匹配 Steam macOS 2.31 ARM64 游戏文件；请使用该版本完整的 Cyberpunk 2077 文件夹。Windows 版或其他版本不能直接代替。\n使用 iPhone / iPad，系统至少 iOS / iPadOS 18。先预留足够空间：本体约 70 GB，全部资源约 96 GB，另留存档和运行空间。",@"This build matches Steam macOS 2.31 ARM64. Use the complete Cyberpunk 2077 folder from that version; Windows files and other versions are not interchangeable.\nUse an iPhone or iPad with iOS / iPadOS 18 or later. Allow about 70 GB for the base game or 96 GB for all resources, plus space for saves and runtime data.")],
        @[CPUIString(@"02 / 签名并安装 IPA",@"02 / Sign and install the IPA"),
          CPUIString(@"用你现有的签名工具安装 IPA，签名必须包含主应用与嵌套动态库；具体按该工具的有效签名安装流程操作。本教程的手机放文件步骤从 IPA 已安装开始。\n更新时沿用相同 Bundle ID 并覆盖安装，保留资源、存档和自定义键位；不要先卸载。安装好后先打开一次启动器，再切到“文件”App。",@"Install the IPA using your existing signing tool; signing must include the app and embedded libraries. Follow that tool's valid signing and installation process. The phone file-placement steps below begin with the IPA already installed.\nFor updates, keep the same Bundle ID and install over the existing app to retain resources, saves and custom controls. Do not uninstall first. Open the launcher once, then switch to Files.")],
        @[CPUIString(@"03 / 只有手机：本体放哪里、怎么放",@"03 / Phone only: where and how to place the game"),phoneImport],
        @[CPUIString(@"04 / 选择设备与画面输出",@"04 / Choose your device and output"),
          CPUIString(@"启动页默认自动识别设备，也可按芯片手动选择。新设备先选 720p，点“开始游戏”保存选择并启动；需要时再对照 1080p。\n720p / 1080p 是全屏输出高度，宽度按屏幕比例调整，内部渲染由 MetalFX 动态缩放。预设以 30 FPS 为目标，实际帧率与发热需要各设备实测。游戏画质和 HDR 选项在游戏设置中调整。",@"The launcher detects your device automatically; you can also select a preset by chip. Start new devices at 720p. Tap Start game to save your selection and launch, then compare 1080p if needed.\n720p / 1080p describes full-screen output height; width follows the screen aspect ratio. MetalFX dynamically scales internal rendering. Presets target 30 FPS; sustained frame rate and temperature require device testing. Adjust game graphics and HDR in the game's settings.")],
        @[CPUIString(@"05 / 手柄、触控与中英文",@"05 / Controller, touch and language"),
          CPUIString(@"实体手柄可直接使用。触屏游玩时，在左半屏空白处按下生成浮动移动摇杆，松手立即隐藏；右半屏空白处滑动转动镜头，没有固定右摇杆。支持同时移动、转视角、瞄准和射击。\n点显示“自动 / 游玩 / 界面”的输入模式按钮切换模式；左、右半屏操作用于游玩模式，界面模式使用菜单点击。点“布局”可拖动按钮，修改功能、大小、透明度、显示开关及镜头灵敏度；完成后点“保存完成”。\n无手指接触约 4 秒后触控按钮自动隐藏，再触摸屏幕唤回。启动页或键位编辑器可切换中文 / English；游戏字幕与配音语言在游戏里单独设置。",@"A physical controller can be used directly. For touch play, press empty space on the left half to create a floating movement stick; it disappears on release. Swipe empty space on the right half to look around, with no fixed right stick. Movement, camera, aiming and firing can be used together.\nTap the input-mode button labeled Auto, Play or UI to cycle modes. Left/right-half gestures work in Play mode; UI mode allows menu taps. Tap Layout to move buttons and edit bindings, size, opacity, visibility and look sensitivity, then choose Save / Done.\nTouch buttons hide after about 4 seconds with no fingers on screen; touch again to reveal them. Switch 中文 / English in the launcher or layout editor. Game subtitles and voice language are configured separately in the game.")],
        @[CPUIString(@"06 / 存档、更新与问题反馈",@"06 / Saves, updates and reporting issues"),
          CPUIString(@"找不到应用文件夹：先打开一次启动器，再在“文件”→“浏览”→“我的 iPhone / iPad”刷新。应用文件夹名以实际安装名称为准。\n提示缺少资源：检查 GuestGame 中是否直接包含 archive、engine、r6 和 Cyberpunk2077.app，不能是 GuestGame/Cyberpunk 2077/archive；确认版本和解压是否完整。\n手机反馈日志：在“文件”里打开应用文件夹的根目录（GuestGame 上一级），长按 probe-report.json 或 performance-*.jsonl，点“共享”发送。存档使用应用自身的可写目录，覆盖更新保留；不要卸载应用来清理资源。\n如有 Mac，也可把“导入正版游戏资源.command”和 Cyberpunk2077-iOS-rebuild-source.zip 放在一起，用 USB 导入。Mac 方式是可选项。",@"If the app folder is missing, open the launcher once, then refresh Files → Browse → On My iPhone / iPad. The folder follows the installed app's actual name.\nFor missing-resource errors, check that GuestGame directly contains archive, engine, r6 and Cyberpunk2077.app, rather than GuestGame/Cyberpunk 2077/archive. Confirm the version and complete extraction.\nTo share logs from the phone, open the app folder's root (the parent of GuestGame), hold probe-report.json or performance-*.jsonl and tap Share. Saves use the app's writable storage and survive same-ID updates; do not uninstall to clear resources.\nA Mac is optional: put 导入正版游戏资源.command alongside Cyberpunk2077-iOS-rebuild-source.zip and use USB import if desired.")]
    ];
    for(NSUInteger index=0;index<sections.count;index++){
        NSArray *section=sections[index];UILabel *heading=CPGuideLabel(section[0],16,YES),*body=CPGuideLabel(section[1],14,NO);
        body.accessibilityIdentifier=[NSString stringWithFormat:@"guide-section-%lu",(unsigned long)(index+1)];
        UIStackView *block=[[UIStackView alloc] initWithArrangedSubviews:@[heading,body]];block.axis=UILayoutConstraintAxisVertical;block.spacing=8;[stack addArrangedSubview:block];
        if(index==2){
            self.phoneSection=block;
            UILabel *tree=CPGuideLabel(@"GuestGame/\n├─ archive/Mac/…\n├─ engine/…\n├─ r6/cache/tweakdb.bin\n└─ Cyberpunk2077.app/Contents/…",13,NO);
            tree.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];tree.textColor=CPGuideCyan();tree.accessibilityIdentifier=@"game-folder-tree";[block addArrangedSubview:tree];
        }
    }
    UILabel *footer=CPGuideLabel(CPUIString(@"启动器 · DingElero\n完全免费，需要自备正版游戏。",@"Launcher · DingElero\nCompletely free. Your own legitimate game files are required."),12,NO);footer.textColor=CPGuideCyan();[stack addArrangedSubview:footer];
}
- (void)showPhoneSteps {
    [self.view layoutIfNeeded];CGRect rect=[self.phoneSection convertRect:self.phoneSection.bounds toView:self.guideScroll];
    CGFloat maximum=MAX(0,self.guideScroll.contentSize.height-self.guideScroll.bounds.size.height);
    [self.guideScroll setContentOffset:CGPointMake(0,MIN(maximum,MAX(0,rect.origin.y))) animated:NO];
}
- (void)close {[self dismissViewControllerAnimated:YES completion:nil];}
@end
