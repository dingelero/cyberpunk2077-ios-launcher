// Simulator component harness. No commercial game, device input or JIT.
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import "compat/TouchControls.h"
#import "compat/AppKitBridge.h"
#import "compat/TouchInput.h"
static NSMutableDictionary *Events;
static NSMutableDictionary *Components;
static UILabel *Status;
static NSHashTable *Registered;
static GCController *Fixture;
static double StartedAt;
static void Save(void);
extern int32_t CGAssociateMouseAndMouseCursorPosition(bool);
static void Observe(GCController *controller) {
    if(!controller || [Registered containsObject:controller])return;[Registered addObject:controller];controller.handlerQueue=dispatch_get_main_queue();
    GCExtendedGamepad *p=controller.extendedGamepad;
    NSArray *names=@[@"A",@"B",@"X",@"Y",@"LT",@"RT",@"LB",@"RB",@"L3",@"R3",@"menu",@"view",@"up",@"down",@"left",@"right"];
    NSArray *buttons=@[p.buttonA,p.buttonB,p.buttonX,p.buttonY,p.leftTrigger,p.rightTrigger,p.leftShoulder,p.rightShoulder,p.leftThumbstickButton,p.rightThumbstickButton,p.buttonMenu,p.buttonOptions,p.dpad.up,p.dpad.down,p.dpad.left,p.dpad.right];
    for(unsigned i=0;i<buttons.count;i++) {
        NSString *name=names[i];GCControllerButtonInput *button=buttons[i];
        button.valueChangedHandler=^(__unused GCControllerButtonInput *input,float value,__unused BOOL pressed){
            Events[name]=@([Events[name] unsignedIntegerValue]+1);Events[[@"last" stringByAppendingString:name]]=@(value);Save();
        };
    }
    p.leftThumbstick.valueChangedHandler=^(__unused GCControllerDirectionPad *input,float x,float y){
        Events[@"leftStick"]=@([Events[@"leftStick"] unsignedIntegerValue]+1);Events[@"lastLeftStick"]=@[@(x),@(y)];Save();
    };
    p.rightThumbstick.valueChangedHandler=^(__unused GCControllerDirectionPad *input,float x,float y){
        Events[@"rightStick"]=@([Events[@"rightStick"] unsignedIntegerValue]+1);Events[@"lastRightStick"]=@[@(x),@(y)];Save();
    };
}
static void Save(void) {
    Observe(CPTouchNativeController());
    NSDictionary *sample=@{@"pid":@(getpid()),@"startedAt":@(StartedAt),@"touch":CPTouchControlsReport(),@"events":Events ?: @{},
        @"components":Components ?: @{},@"gameLoaded":@NO,@"physicalPhoneTested":@NO,@"timestamp":@(NSDate.date.timeIntervalSince1970)};
    NSData *data=[NSJSONSerialization dataWithJSONObject:sample options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/touch-probe.json"] atomically:YES];
    NSString *history=[NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/touch-v3-history-%d.jsonl",getpid()]];
    if(![NSFileManager.defaultManager fileExistsAtPath:history])[NSFileManager.defaultManager createFileAtPath:history contents:nil attributes:nil];
    NSFileHandle *log=[NSFileHandle fileHandleForWritingAtPath:history];[log seekToEndOfFile];
    NSMutableData *row=[[NSJSONSerialization dataWithJSONObject:sample options:0 error:nil] mutableCopy];[row appendBytes:"\n" length:1];[log writeData:row];[log closeFile];
    Status.text=[NSString stringWithFormat:@"TOUCH INTERFACE // 2077\n左侧浮动移动 · 右侧滑动视角\n%@\n原生按键事件 %@\n组件测试，不包含游戏",
        Components[@"passed"]?@"组件检查通过":@"组件检查中",Events[@"RT"] ?: @0];
}
@interface CPProbeNativeView:NSView @end
@implementation CPProbeNativeView
- (void)mouseMoved:(NSEvent *)event {
    Events[@"cameraX"]=@([Events[@"cameraX"] doubleValue]+event.deltaX);Events[@"cameraY"]=@([Events[@"cameraY"] doubleValue]+event.deltaY);
    Events[@"cameraEvents"]=@([Events[@"cameraEvents"] unsignedIntegerValue]+1);Save();
}
- (void)keyDown:(NSEvent *)event {Events[[NSString stringWithFormat:@"key-%u-down",event.keyCode]]=@([Events[[NSString stringWithFormat:@"key-%u-down",event.keyCode]] unsignedIntegerValue]+1);Save();}
- (void)keyUp:(NSEvent *)event {Events[[NSString stringWithFormat:@"key-%u-up",event.keyCode]]=@([Events[[NSString stringWithFormat:@"key-%u-up",event.keyCode]] unsignedIntegerValue]+1);Save();}
- (void)mouseDown:(NSEvent *)event {Events[@"menuClickDown"]=@([Events[@"menuClickDown"] unsignedIntegerValue]+1);Save();}
- (void)mouseUp:(NSEvent *)event {Events[@"menuClickUp"]=@([Events[@"menuClickUp"] unsignedIntegerValue]+1);Save();}
@end
static void ComponentChecks(void) {
    Components=[NSMutableDictionary new];Fixture=[GCController controllerWithExtendedGamepad];Fixture.handlerQueue=dispatch_get_main_queue();
    GCExtendedGamepad *p=Fixture.extendedGamepad;NSMutableDictionary *callbacks=[NSMutableDictionary new];
    NSArray *buttons=@[p.buttonA,p.buttonB,p.buttonX,p.buttonY,p.leftTrigger,p.rightTrigger,p.leftShoulder,p.rightShoulder,p.leftThumbstickButton,p.rightThumbstickButton,p.buttonMenu,p.buttonOptions];
    for(unsigned i=0;i<buttons.count;i++) {
        NSString *name=[NSString stringWithFormat:@"button-%u",i];
        [buttons[i] setValueChangedHandler:^(__unused GCControllerButtonInput *input,__unused float v,__unused BOOL down){callbacks[name]=@([callbacks[name] unsignedIntegerValue]+1);}];
    }
    p.leftThumbstick.valueChangedHandler=^(__unused GCControllerDirectionPad *input,__unused float x,__unused float y){callbacks[@"move"]=@([callbacks[@"move"] unsignedIntegerValue]+1);};
    p.dpad.valueChangedHandler=^(__unused GCControllerDirectionPad *input,__unused float x,__unused float y){callbacks[@"dpad"]=@([callbacks[@"dpad"] unsignedIntegerValue]+1);};
    CPTouchRouter router={0};CPTouchContact *move=CPTouchBegin(&router,1,CPTouchMove,-1,120,200),*look=CPTouchBegin(&router,2,CPTouchLook,-1,610,180);
    CPTouchBegin(&router,3,CPTouchButton,0,50,60);CPTouchBegin(&router,4,CPTouchButton,1,860,60);
    CPTouchAxis a=CPTouchMovement(move,142,182,46);CPTouchDelta d=CPTouchRelativeLook(look,640,186,1.6,0);
    [p.leftThumbstick setValueForXAxis:a.x yAxis:a.y];for(GCControllerButtonInput *button in buttons)[button setValue:1];[p.dpad setValueForXAxis:-1 yAxis:1];
    Components[@"simultaneousMoveAimFireState"]=@(p.leftThumbstick.xAxis.value>0 && p.leftTrigger.value==1 && p.rightTrigger.value==1 && d.x>0);
    Components[@"fourContactModelRoles"]=@(router.move==1 && router.look==2 && CPTouchFind(&router,3)->role==CPTouchButton && CPTouchFind(&router,4)->role==CPTouchButton);
    // Test the real production event queue without injecting UITouch objects.
    [NSApp.events removeAllObjects];
    for(unsigned i=0;i<240;i++)CPAppKitPostRelativeLook(CGPointMake(1.25,-0.5),NSProcessInfo.processInfo.systemUptime);
    NSEvent *one=NSApp.events.firstObject;Components[@"relativeQueuePreservesFullDisplacement"]=@(NSApp.events.count==1 && one.deltaX==300 && one.deltaY==-120);
    NSEvent *key=[NSEvent new];key.type=10;key.keyCode=36;[NSApp postEvent:key atStart:NO];CPAppKitPostRelativeLook(CGPointMake(2,3),NSProcessInfo.processInfo.systemUptime);
    Components[@"relativeQueuePreservesButtonOrdering"]=@(NSApp.events.count==3 && NSApp.events[1].type==10);[NSApp.events removeAllObjects];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        BOOL all=YES;for(unsigned i=0;i<buttons.count;i++)if([callbacks[[NSString stringWithFormat:@"button-%u",i]] unsignedIntegerValue]!=1)all=NO;
        Components[@"allTwelveNativeButtonCallbacksDeliveredOnce"]=@(all);Components[@"nativeL3R3MenuViewAvailable"]=@(p.leftThumbstickButton && p.rightThumbstickButton && p.buttonMenu && p.buttonOptions);
        Components[@"nativeMoveCallbackDelivered"]=@([callbacks[@"move"] unsignedIntegerValue]>0);Components[@"nativeDpadCallbackDelivered"]=@([callbacks[@"dpad"] unsignedIntegerValue]>0);
        for(GCControllerButtonInput *button in buttons)[button setValue:0];[p.leftThumbstick setValueForXAxis:0 yAxis:0];[p.dpad setValueForXAxis:0 yAxis:0];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,180*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            BOOL zero=YES;for(GCControllerButtonInput *button in buttons)if(button.value!=0)zero=NO;
            Components[@"allNativeInputsReleasedToZero"]=@(zero && p.leftThumbstick.xAxis.value==0 && p.leftThumbstick.yAxis.value==0 && p.dpad.xAxis.value==0 && p.dpad.yAxis.value==0);
            BOOL passed=YES;for(id v in Components.allValues)if(![v boolValue])passed=NO;Components[@"passed"]=@(passed);
            Components[@"scope"]=@"Production router + native software pad + AppKit queue; no OS multi-finger injection, no commercial game";
            Save();
        });
    });
}
@interface CPProbeController:UIViewController @end
@implementation CPProbeController
- (BOOL)prefersStatusBarHidden{return YES;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations{return UIInterfaceOrientationMaskLandscape;}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation{return UIInterfaceOrientationLandscapeRight;}
@end
@interface CPProbeScene:UIResponder<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation CPProbeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    setenv("CP_TOUCH_SIMULATOR_PROBE","1",1);StartedAt=NSDate.date.timeIntervalSince1970;
    Events=[NSMutableDictionary new];Registered=[NSHashTable weakObjectsHashTable];self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];self.window.rootViewController=[CPProbeController new];
    UIView *root=self.window.rootViewController.view;root.backgroundColor=[UIColor colorWithRed:0.018 green:0.035 blue:0.045 alpha:1];[self.window makeKeyAndVisible];
    CPAppKitBindHostWindow(self.window);NSWindow *native=[NSWindow new];native.windowNumber=1;native.nativeWindow=self.window;
    CPProbeNativeView *canvas=[[CPProbeNativeView alloc] initWithFrame:root.bounds];native.contentView=canvas;
    [NSApp.windows addObject:native];NSApp.keyWindow=native;NSApp.mainWindow=native;
    Status=[[UILabel alloc] initWithFrame:canvas.nativeView.bounds];Status.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    Status.textColor=[UIColor colorWithRed:0.2 green:0.9 blue:0.98 alpha:1];Status.font=[UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    Status.numberOfLines=0;Status.textAlignment=NSTextAlignmentCenter;Status.userInteractionEnabled=NO;[canvas.nativeView addSubview:Status];
    CPAttachTouchControls(self.window);CGAssociateMouseAndMouseCursorPosition(false);
    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(__unused NSTimer *t){
        for(unsigned i=0;i<100;i++){NSEvent *event=[NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.date inMode:NSDefaultRunLoopMode dequeue:YES];if(!event)break;[NSApp sendEvent:event];}
    }];
    [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(__unused NSTimer *t){Save();}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ComponentChecks();});
    Save();
}
@end
@interface CPProbeDelegate:UIResponder<UIApplicationDelegate> @end
@implementation CPProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options{return YES;}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *config=[[UISceneConfiguration alloc] initWithName:@"TouchProbe" sessionRole:session.role];config.delegateClass=CPProbeScene.class;return config;
}
@end
int main(int argc,char *argv[]) {@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(CPProbeDelegate.class));}}
