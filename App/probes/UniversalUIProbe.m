// Native UIKit component QA. This executable never loads commercial code.
#import <UIKit/UIKit.h>
#import "LaunchMenu.h"
#import "LaunchGuide.h"
#import "LaunchPreferences.h"
#import "PerformanceProfile.h"
#import "DisplayPolicy.h"
#import "compat/UILanguage.h"
#import "compat/TouchControls.h"
#import "compat/AppKitBridge.h"
static NSMutableDictionary *Results;
extern CFArrayRef CGDisplayCopyAllDisplayModes(uint32_t,CFDictionaryRef);
void CPHostRecordEvent(NSString *key,id value){Results[key]=value ?: NSNull.null;}
static void Require(BOOL passed,NSString *message){Results[message]=@(passed);NSCAssert(passed,@"%@",message);}
static void Save(void){
    Results[@"scope"]=[NSProcessInfo.processInfo.arguments containsObject:@"--qa-branding"]?@"Production launcher branding and offline tutorial only in Simulator. No commercial game, physical device or touch input.":@"Production UIKit launcher, display policy and touch editor in Simulator. No game, device GPU or physical touch input.";
    Results[@"physicalDeviceGameplayVerified"]=@NO;
    [[NSJSONSerialization dataWithJSONObject:Results options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/universal-ui-probe.json"] atomically:YES];
}
static UIView *Find(UIView *root,NSString *identifier){if([root.accessibilityIdentifier isEqual:identifier])return root;for(UIView *child in root.subviews){UIView *found=Find(child,identifier);if(found)return found;}return nil;}
static BOOL Text(UIView *root,NSString *text){if([root isKindOfClass:UILabel.class] && [[(UILabel *)root text] isEqual:text])return YES;for(UIView *child in root.subviews)if(Text(child,text))return YES;return NO;}
@interface CPProbeScene:UIResponder<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation CPProbeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    Results=[NSMutableDictionary new];setenv("CP_TOUCH_SIMULATOR_PROBE","1",1);
    const char *language=getenv("CP_PROBE_LANGUAGE");if(language)CPSetUILanguage(@(language));
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];CPLaunchMenu *menu=[CPLaunchMenu new];self.window.rootViewController=menu;[self.window makeKeyAndVisible];
    __weak CPProbeScene *weak=self;
    menu.startGame=^{[weak exerciseDisplayAndTouch];};
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        UIButton *start=(UIButton *)Find(menu.view,@"start-game");Require(start!=nil,@"launcherStartButtonPresent");
        Results[@"screenBounds"]=NSStringFromCGRect(self.window.screen.bounds);Results[@"uiLanguage"]=CPUILanguage();Save();
        if([NSProcessInfo.processInfo.arguments containsObject:@"--show-guide"]){[(UIButton *)Find(menu.view,@"launch-guide-button") sendActionsForControlEvents:UIControlEventTouchUpInside];return;}
        if([NSProcessInfo.processInfo.arguments containsObject:@"--qa-branding"]){[self exerciseBranding:menu language:0];return;}
        if([NSProcessInfo.processInfo.arguments containsObject:@"--qa-flow"]){
            UISegmentedControl *language=(UISegmentedControl *)Find(menu.view,@"ui-language");language.selectedSegmentIndex=1;[language sendActionsForControlEvents:UIControlEventValueChanged];
            Require([[(UIButton *)Find(menu.view,@"start-game") titleForState:UIControlStateNormal] isEqual:@"Start game"],@"launcherEnglishSwitchApplied");
            UISegmentedControl *resolution=(UISegmentedControl *)Find(menu.view,@"output-resolution");resolution.selectedSegmentIndex=1;[resolution sendActionsForControlEvents:UIControlEventValueChanged];
            [(UIButton *)Find(menu.view,@"start-game") sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
    });
}
- (void)exerciseBranding:(CPLaunchMenu *)menu language:(NSInteger)index {
    UISegmentedControl *language=(UISegmentedControl *)Find(menu.view,@"ui-language");language.selectedSegmentIndex=index;[language sendActionsForControlEvents:UIControlEventValueChanged];
    [menu.view layoutIfNeeded];NSString *suffix=index?@"English":@"Chinese";
    UIImageView *logo=(UIImageView *)Find(menu.view,@"dingelero-logo");
    Require(logo.image.CGImage && CGImageGetWidth(logo.image.CGImage)==512 && CGImageGetHeight(logo.image.CGImage)==512,@"personalLogoLoadedFromBundle");
    Require([[(UILabel *)Find(menu.view,@"launcher-credit") text] containsString:@"DingElero"],@"DingEleroCreditVisible");
    BOOL isDirectory=NO;Require([NSFileManager.defaultManager fileExistsAtPath:CPGameFilesPath() isDirectory:&isDirectory] && isDirectory,@"GuestGameCreatedOnFirstLauncherOpen");
    Require([[(UILabel *)Find(menu.view,@"game-files-location") text] isEqual:CPGameFilesLocation()],@"visibleFilesRouteMatchesGuestGameLocation");
    NSString *requirements=[(UILabel *)Find(menu.view,@"launcher-requirements") text];
    Require([requirements containsString:index?@"Completely free":@"完全免费"] && [requirements containsString:@"Steam macOS"],[suffix stringByAppendingString:@"FreeAndOwnSteamFilesNotice"]);
    NSDictionary *preferences=[[menu valueForKey:@"preferences"] copy];
    UIButton *guide=(UIButton *)Find(menu.view,@"launch-guide-button");Require(guide!=nil,@"tutorialButtonPresent");[guide sendActionsForControlEvents:UIControlEventTouchUpInside];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.7*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        UINavigationController *navigation=(UINavigationController *)menu.presentedViewController;
        UIViewController *page=navigation.topViewController;[page.view layoutIfNeeded];
        Require(Find(page.view,@"launch-guide")!=nil,[suffix stringByAppendingString:@"TutorialOpened"]);
        Require([page.title isEqual:index?@"How to play":@"使用教程"],[suffix stringByAppendingString:@"TutorialTitleLocalized"]);
        for(NSUInteger section=1;section<=6;section++)Require(Find(page.view,[NSString stringWithFormat:@"guide-section-%lu",(unsigned long)section])!=nil,@"allSixTutorialSectionsPresent");
        NSString *import=[(UILabel *)Find(page.view,@"guide-section-3") text];
        Require([import containsString:CPGameFilesLocation()] && [import containsString:@"Cyberpunk2077.app"] && [import containsString:@"archive"] && Find(page.view,@"game-folder-tree")!=nil,[suffix stringByAppendingString:@"PhoneOnlyPlacementInstructionsPresent"]);
        Require([[(UILabel *)Find(page.view,@"guide-files-location") text] isEqual:CPGameFilesLocation()],@"FilesLocationVisibleAtTutorialTop");
        UIButton *jump=(UIButton *)Find(page.view,@"jump-to-phone-import");Require(jump!=nil,@"phoneInstructionsJumpButtonPresent");[jump sendActionsForControlEvents:UIControlEventTouchUpInside];
        UIView *section=Find(page.view,@"guide-section-3").superview;CGRect sectionRect=[section convertRect:section.bounds toView:page.view];
        Require(CGRectGetMinY(sectionRect)>=-1 && CGRectGetMinY(sectionRect)<CGRectGetHeight(page.view.bounds)/2,@"phoneInstructionsJumpReachesSectionStart");
        UIScrollView *scroll=(UIScrollView *)Find(page.view,@"launch-guide-scroll");
        Require(scroll.contentSize.height>scroll.bounds.size.height,@"tutorialScrollsOnLandscapeScreen");
        [scroll setContentOffset:CGPointMake(0,scroll.contentSize.height-scroll.bounds.size.height) animated:NO];
        UILabel *last=(UILabel *)Find(page.view,@"guide-section-6");CGRect rect=[last convertRect:last.bounds toView:page.view];
        Require(CGRectIntersectsRect(page.view.bounds,rect),@"lastTutorialSectionReachable");
        UIBarButtonItem *close=page.navigationItem.rightBarButtonItem;
        Require([close.accessibilityIdentifier isEqual:@"close-launch-guide"],@"tutorialBackButtonPresent");
        [UIApplication.sharedApplication sendAction:close.action to:close.target from:close forEvent:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.7*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
            Require(menu.presentedViewController==nil && Find(menu.view,@"start-game")!=nil,@"tutorialReturnsToLauncher");
            Require([[menu valueForKey:@"preferences"] isEqual:preferences],@"readingTutorialPreservesDeviceOptions");
            if(index==0){[self exerciseBranding:menu language:1];return;}
            Results[@"uiLanguage"]=CPUILanguage();Results[@"passed"]=@YES;Results[@"scope"]=@"Production launcher branding and offline tutorial only; no commercial game or phone interaction.";Save();
        });
    });
}
- (void)exerciseDisplayAndTouch {
    NSError *error=nil;
    Require(CPPreparePerformanceFiles(@"",&error),error.localizedDescription ?: @"performanceFilesPrepared");
    Require(CPApplyDisplayPolicy(self.window,&error),error.localizedDescription ?: @"displayPolicyApplied");
    Results[@"firstDisplayPolicy"]=Results[@"displayPolicy"];
    Require(CPApplyDisplayPolicy(self.window,&error) && ![Results[@"displayPolicy"][@"settingsChanged"] boolValue],@"displayPolicySecondLaunchPreservesSettings");
    NSDictionary *profile=CPPerformanceDeviceProfile();Require([profile[@"outputHeight"] isEqual:@1080],@"selected1080OutputPersisted");
    CPAppKitBindHostWindow(self.window);NSWindow *native=[NSWindow new];native.nativeWindow=self.window;native.windowNumber=1;
    NSView *canvas=[[NSView alloc] initWithFrame:self.window.rootViewController.view.bounds];native.contentView=canvas;
    [NSApp.windows addObject:native];NSApp.keyWindow=native;NSApp.mainWindow=native;
    NSArray *modes=CFBridgingRelease(CGDisplayCopyAllDisplayModes(1,NULL));
    CGSize size720=CPOutputRenderSize(self.window.screen.bounds.size,720),size1080=CPOutputRenderSize(self.window.screen.bounds.size,1080);
    BOOL found720=NO,found1080=NO;for(NSDictionary *mode in modes) {
        if([mode[@"width"] doubleValue]==size720.width && [mode[@"height"] doubleValue]==720)found720=YES;
        if([mode[@"width"] doubleValue]==size1080.width && [mode[@"height"] doubleValue]==1080)found1080=YES;
    }
    Require(found720 && found1080,@"bothFullScreenModesExposedToGuest");Results[@"displayModes"]=modes;
    CPAttachTouchControls(self.window);UIView *overlay=nil;for(UIView *view in self.window.subviews)if([NSStringFromClass(view.class) isEqual:@"CPTouchOverlay"])overlay=view;
    Require(overlay!=nil,@"touchOverlayAttached");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [overlay performSelector:NSSelectorFromString(@"beginEditing")];
    UISlider *sizeSlider=[overlay valueForKey:@"sizeSlider"];sizeSlider.value=1.12;[sizeSlider sendActionsForControlEvents:UIControlEventValueChanged];
    NSDictionary *before=[NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:CPTouchControlsReport()[@"settings"] options:0 error:NULL] options:0 error:NULL];
    Require(Text(overlay,@"Fire") && Text(overlay,@"Look speed"),@"englishHUDAndEditorPresent");
    UIButton *toggle=(UIButton *)Find(overlay,@"touch-language");Require(toggle!=nil,@"inGameLanguageTogglePresent");[toggle sendActionsForControlEvents:UIControlEventTouchUpInside];
    Require([CPUILanguage() isEqual:@"zh"] && Text(overlay,@"镜头灵敏度"),@"inGameChineseSwitchApplied");
    [(UIButton *)Find(overlay,@"touch-language") sendActionsForControlEvents:UIControlEventTouchUpInside];
    Require([CPUILanguage() isEqual:@"en"] && [before isEqual:CPTouchControlsReport()[@"settings"]],@"languageSwitchPreservesTouchLayout");
    [overlay performSelector:NSSelectorFromString(@"finishEditing")];
    [overlay performSelector:NSSelectorFromString(@"beginEditing")];
    Require(Text(overlay,@"Fire") && Text(overlay,@"Look speed"),@"englishSurvivesEditorReopen");
#pragma clang diagnostic pop
    Results[@"touch"]=CPTouchControlsReport();Results[@"passed"]=@YES;Save();
}
@end
@interface CPProbeDelegate:UIResponder<UIApplicationDelegate> @end
@implementation CPProbeDelegate
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration=[[UISceneConfiguration alloc] initWithName:@"UniversalProbe" sessionRole:session.role];configuration.delegateClass=CPProbeScene.class;return configuration;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(CPProbeDelegate.class));}}
