#import "LaunchMenu.h"
#import "LaunchPreferences.h"
#import "LaunchGuide.h"
#import "compat/UILanguage.h"
#import <Metal/Metal.h>
@interface CPLaunchMenu ()
@property(nonatomic,strong) NSMutableDictionary *preferences;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) UIButton *profileButton;
@property(nonatomic,copy) NSString *gpuName;
@property(nonatomic,copy) NSString *folderError;
@end
@implementation CPLaunchMenu
- (void)viewDidLoad {
    [super viewDidLoad];self.preferences=CPLoadLaunchPreferences();self.gpuName=MTLCreateSystemDefaultDevice().name ?: @"Apple GPU";
    NSError *error=nil;if(![NSFileManager.defaultManager createDirectoryAtPath:CPGameFilesPath() withIntermediateDirectories:YES attributes:nil error:&error])self.folderError=error.localizedDescription;
    self.view.backgroundColor=[UIColor colorWithRed:0.018 green:0.032 blue:0.043 alpha:1];[self buildMenu];
}
- (BOOL)prefersStatusBarHidden{return YES;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskLandscape;}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation{return UIInterfaceOrientationLandscapeRight;}
- (UILabel *)label:(NSString *)text size:(CGFloat)size {
    UILabel *label=[UILabel new];label.text=text;label.textColor=[UIColor colorWithRed:0.25 green:0.91 blue:0.98 alpha:1];
    label.font=[UIFont systemFontOfSize:size];label.numberOfLines=0;return label;
}
- (UIButton *)button:(NSString *)text action:(SEL)action {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:text forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithRed:0.99 green:0.88 blue:0.11 alpha:1] forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];button.titleLabel.numberOfLines=2;button.titleLabel.textAlignment=NSTextAlignmentCenter;
    button.layer.borderWidth=1;button.layer.borderColor=[UIColor colorWithRed:0.2 green:0.9 blue:0.98 alpha:0.7].CGColor;button.layer.cornerRadius=4;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return button;
}
- (UIStackView *)row:(NSString *)text control:(UIView *)control {
    if([control isKindOfClass:UISegmentedControl.class]) {
        UISegmentedControl *segments=(UISegmentedControl *)control;
        segments.selectedSegmentTintColor=[UIColor colorWithRed:0.99 green:0.88 blue:0.11 alpha:1];
        [segments setTitleTextAttributes:@{NSForegroundColorAttributeName:[UIColor colorWithRed:0.25 green:0.91 blue:0.98 alpha:1]} forState:UIControlStateNormal];
        [segments setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.blackColor} forState:UIControlStateSelected];
    }
    UILabel *label=[self label:text size:14];[label.widthAnchor constraintEqualToConstant:108].active=YES;
    UIStackView *row=[[UIStackView alloc] initWithArrangedSubviews:@[label,control]];row.axis=UILayoutConstraintAxisHorizontal;row.spacing=12;row.alignment=UIStackViewAlignmentCenter;return row;
}
- (UIView *)branding {
    UIImageView *logo=[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"LauncherAssets/DingElero.png"]];
    logo.contentMode=UIViewContentModeScaleAspectFit;logo.layer.minificationFilter=kCAFilterNearest;logo.layer.magnificationFilter=kCAFilterNearest;
    logo.layer.borderWidth=1;logo.layer.borderColor=[UIColor colorWithRed:0.25 green:0.91 blue:0.98 alpha:0.8].CGColor;
    logo.accessibilityIdentifier=@"dingelero-logo";logo.isAccessibilityElement=YES;logo.accessibilityLabel=@"DingElero";
    [NSLayoutConstraint activateConstraints:@[[logo.widthAnchor constraintEqualToConstant:64],[logo.heightAnchor constraintEqualToConstant:64]]];
    UILabel *title=[self label:@"CYBERPUNK 2077 // MOBILE" size:20];title.font=[UIFont systemFontOfSize:20 weight:UIFontWeightBold];title.textColor=[UIColor colorWithRed:0.99 green:0.88 blue:0.11 alpha:1];
    UILabel *credit=[self label:CPUIString(@"DingElero // 免费启动器",@"DingElero // FREE LAUNCHER") size:13];credit.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];credit.accessibilityIdentifier=@"launcher-credit";
    UILabel *hardware=[self label:[NSString stringWithFormat:@"%@ · %.1f GB",self.gpuName,NSProcessInfo.processInfo.physicalMemory/(double)(1ULL<<30)] size:11];hardware.textColor=[UIColor colorWithRed:0.62 green:0.73 blue:0.78 alpha:1];
    UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[title,credit,hardware]];text.axis=UILayoutConstraintAxisVertical;text.spacing=3;
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[logo,text]];header.spacing=14;header.alignment=UIStackViewAlignmentCenter;return header;
}
- (void)buildMenu {
    for(UIView *view in self.view.subviews)[view removeFromSuperview];
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor]]];
    scroll.accessibilityIdentifier=@"launch-menu-scroll";scroll.indicatorStyle=UIScrollViewIndicatorStyleWhite;
    self.stack=[UIStackView new];self.stack.axis=UILayoutConstraintAxisVertical;self.stack.spacing=10;self.stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:self.stack];
    NSLayoutConstraint *width=[self.stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40];width.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[[self.stack.centerXAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.centerXAnchor],
        [self.stack.widthAnchor constraintLessThanOrEqualToConstant:680],width,
        [self.stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[self.stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16]]];
    [self.stack addArrangedSubview:[self branding]];
    UILabel *requirements=[self label:CPUIString(@"本启动器完全免费。请自备正版 Cyberpunk 2077 Steam macOS 版游戏文件。",@"Completely free launcher. Your own legitimate Cyberpunk 2077 Steam macOS game files are required.") size:13];
    requirements.textColor=[UIColor colorWithRed:0.78 green:0.86 blue:0.90 alpha:1];requirements.accessibilityIdentifier=@"launcher-requirements";[self.stack addArrangedSubview:requirements];
    UILabel *location=[self label:self.folderError ?: CPGameFilesLocation() size:12];location.accessibilityIdentifier=@"game-files-location";
    if(self.folderError)location.textColor=UIColor.systemRedColor;[self.stack addArrangedSubview:location];
    self.profileButton=[self button:@"" action:@selector(chooseProfile)];self.profileButton.accessibilityIdentifier=@"device-profile";
    [self.stack addArrangedSubview:[self row:CPUIString(@"设备预设",@"Device preset") control:self.profileButton]];[self refreshProfile];
    UISegmentedControl *resolution=[[UISegmentedControl alloc] initWithItems:@[@"720p",@"1080p"]];resolution.selectedSegmentIndex=[self.preferences[@"outputHeight"] isEqual:@1080]?1:0;
    resolution.accessibilityIdentifier=@"output-resolution";[resolution addTarget:self action:@selector(changeResolution:) forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:[self row:CPUIString(@"全屏输出",@"Full-screen") control:resolution]];
    UISegmentedControl *language=[[UISegmentedControl alloc] initWithItems:@[@"中文",@"English"]];language.selectedSegmentIndex=[CPUILanguage() isEqual:@"en"]?1:0;
    language.accessibilityIdentifier=@"ui-language";[language addTarget:self action:@selector(changeLanguage:) forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:[self row:CPUIString(@"触控 / 界面",@"Touch / UI") control:language]];
    UIScreen *screen=self.view.window.windowScene.screen ?: UIScreen.mainScreen;
    CGSize size=CPOutputRenderSize(screen.bounds.size,[self.preferences[@"outputHeight"] unsignedIntegerValue]);
    NSString *note=[NSString stringWithFormat:CPUIString(@"%.0f × %.0f 全屏输出 · 目标 30 FPS\nMetalFX 动态内部渲染；1080p 负载更高。新设备先从 720p 测试。",@"%.0f × %.0f full-screen output · target 30 FPS\nMetalFX scales internal rendering dynamically. Start new devices at 720p; 1080p increases load."),size.width,size.height];
    [self.stack addArrangedSubview:[self label:note size:12]];
    UIButton *start=[self button:CPUIString(@"开始游戏",@"Start game") action:@selector(start)];start.accessibilityIdentifier=@"start-game";
    start.backgroundColor=[UIColor colorWithRed:0.10 green:0.12 blue:0.035 alpha:1];
    UIButton *guide=[self button:CPUIString(@"使用教程",@"How to play") action:@selector(showGuide)];guide.accessibilityIdentifier=@"launch-guide-button";
    UIStackView *actions=[[UIStackView alloc] initWithArrangedSubviews:@[start,guide]];actions.spacing=12;[start.widthAnchor constraintEqualToAnchor:guide.widthAnchor multiplier:1.7].active=YES;[self.stack addArrangedSubview:actions];
}
- (void)viewDidAppear:(BOOL)animated {[super viewDidAppear:animated];[self buildMenu];}
- (void)refreshProfile {
    NSDictionary *profile=CPResolveLaunchProfile(self.preferences,self.gpuName,UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad);
    NSString *name=profile[[CPUILanguage() isEqual:@"en"]?@"title_en":@"title"];
    if([self.preferences[@"profile"] isEqual:@"auto"])name=[NSString stringWithFormat:@"%@ · %@",CPUIString(@"自动",@"Auto"),name];
    [self.profileButton setTitle:name forState:UIControlStateNormal];
}
- (void)chooseProfile {
    UIAlertController *list=[UIAlertController alertControllerWithTitle:CPUIString(@"设备预设",@"Device preset") message:CPUIString(@"按芯片选择；每项均可使用 720p 或 1080p。其他设备的性能由实测确定。",@"Choose by chip. Every preset offers 720p and 1080p; performance requires device testing.") preferredStyle:UIAlertControllerStyleActionSheet];
    NSMutableArray *profiles=[NSMutableArray arrayWithObject:@{@"id":@"auto",@"title":@"自动识别",@"title_en":@"Detect automatically"}];[profiles addObjectsFromArray:CPDeviceProfiles()];
    for(NSDictionary *profile in profiles)[list addAction:[UIAlertAction actionWithTitle:profile[[CPUILanguage() isEqual:@"en"]?@"title_en":@"title"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){self.preferences[@"profile"]=profile[@"id"];[self buildMenu];}]];
    [list addAction:[UIAlertAction actionWithTitle:CPUIString(@"取消",@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    list.popoverPresentationController.sourceView=self.profileButton;list.popoverPresentationController.sourceRect=self.profileButton.bounds;[self presentViewController:list animated:YES completion:nil];
}
- (void)changeResolution:(UISegmentedControl *)control {self.preferences[@"outputHeight"]=control.selectedSegmentIndex==1?@1080:@720;[self buildMenu];}
- (void)changeLanguage:(UISegmentedControl *)control {CPSetUILanguage(control.selectedSegmentIndex==1?@"en":@"zh");[self buildMenu];}
- (void)showGuide {
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:[CPLaunchGuide new]];
    navigation.modalPresentationStyle=UIModalPresentationFullScreen;navigation.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];[appearance configureWithOpaqueBackground];
    appearance.backgroundColor=self.view.backgroundColor;appearance.titleTextAttributes=@{NSForegroundColorAttributeName:[UIColor colorWithRed:0.99 green:0.88 blue:0.11 alpha:1]};
    navigation.navigationBar.standardAppearance=appearance;navigation.navigationBar.scrollEdgeAppearance=appearance;
    navigation.navigationBar.tintColor=[UIColor colorWithRed:0.25 green:0.91 blue:0.98 alpha:1];[self presentViewController:navigation animated:YES completion:nil];
}
- (void)start {CPSaveLaunchPreferences(self.preferences);if(self.startGame)self.startGame();}
@end
