#import <UIKit/UIKit.h>
#import <TouchController/TouchController.h>
#import <GameController/GameController.h>
#import <Metal/Metal.h>
static TCTouchController *Controller;
static NSMutableArray *Samples;
static void SnapshotProbe(void) {
    GCController *controller=[GCController controllerWithExtendedGamepad];controller.handlerQueue=dispatch_get_main_queue();
    GCExtendedGamepad *p=controller.extendedGamepad;__block unsigned events=0;
    p.valueChangedHandler=^(__unused GCExtendedGamepad *pad,__unused GCControllerElement *element){events++;};
    __block unsigned buttonEvents=0;p.buttonA.valueChangedHandler=^(__unused GCControllerButtonInput *b,__unused float v,__unused BOOL pressed){buttonEvents++;};
    [p.buttonA setValue:1];[p.leftTrigger setValue:1];[p.rightTrigger setValue:1];
    [p.leftThumbstickButton setValue:1];[p.rightThumbstickButton setValue:1];[p.buttonMenu setValue:1];[p.buttonOptions setValue:1];
    [p.leftThumbstick setValueForXAxis:0.4 yAxis:0.7];[p.dpad setValueForXAxis:-1 yAxis:1];
    NSDictionary *report=@{@"touchControllerSupported":@(TCTouchController.supported),@"snapshot":@(controller.isSnapshot),
        @"elementNames":controller.physicalInputProfile.buttons.allKeys,@"A":@(p.buttonA.value),@"LT":@(p.leftTrigger.value),@"RT":@(p.rightTrigger.value),
        @"L3Available":@(p.leftThumbstickButton!=nil),@"L3":@(p.leftThumbstickButton.value),@"R3Available":@(p.rightThumbstickButton!=nil),@"R3":@(p.rightThumbstickButton.value),
        @"menu":@(p.buttonMenu.value),@"optionsAvailable":@(p.buttonOptions!=nil),@"options":@(p.buttonOptions.value),
        @"left":@[@(p.leftThumbstick.xAxis.value),@(p.leftThumbstick.yAxis.value)],@"dpad":@[@(p.dpad.xAxis.value),@(p.dpad.yAxis.value)],@"nativeCallbacks":@(events),@"gameLoaded":@NO};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/backend-probe.json"] atomically:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        NSMutableDictionary *after=[report mutableCopy];after[@"nativeCallbacksAfterWait"]=@(events);after[@"nativeButtonCallbacksAfterWait"]=@(buttonEvents);after[@"controllerRetained"]=@(controller!=nil);
        [[NSJSONSerialization dataWithJSONObject:after options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/backend-probe.json"] atomically:YES];
    });
}
static void Save(NSString *phase) {
    GCExtendedGamepad *p=Controller.controller.extendedGamepad;
    [Samples addObject:@{@"phase":phase,@"A":@(p.buttonA.value),@"L3":@(p.leftThumbstickButton.value),
        @"R3":@(p.rightThumbstickButton.value),@"menu":@(p.buttonMenu.value),@"options":@(p.buttonOptions.value),
        @"left":@[@(p.leftThumbstick.xAxis.value),@(p.leftThumbstick.yAxis.value)],
        @"right":@[@(p.rightThumbstick.xAxis.value),@(p.rightThumbstick.yAxis.value)],
        @"dpad":@[@(p.dpad.xAxis.value),@(p.dpad.yAxis.value)],@"connected":@(Controller.connected),
        @"vendor":Controller.controller.vendorName ?: @"",@"category":Controller.controller.productCategory ?: @""}];
    NSDictionary *report=@{@"supported":@(TCTouchController.supported),@"samples":Samples,@"gameLoaded":@NO};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]
        writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/backend-probe.json"] atomically:YES];
}
static void Step(unsigned index) {
    if(index==0){Save(@"initial");[Controller handleTouchBeganAtPoint:CGPointMake(100,100) index:1];}
    if(index==1){Save(@"A down");[Controller handleTouchBeganAtPoint:CGPointMake(200,100) index:2];[Controller handleTouchBeganAtPoint:CGPointMake(300,100) index:3];}
    if(index==2){Save(@"L3 R3 simultaneous");[Controller handleTouchBeganAtPoint:CGPointMake(200,400) index:4];[Controller handleTouchMovedAtPoint:CGPointMake(230,375) index:4];}
    if(index==3){Save(@"left moved");[Controller handleTouchBeganAtPoint:CGPointMake(600,400) index:5];[Controller handleTouchMovedAtPoint:CGPointMake(625,410) index:5];}
    if(index==4){Save(@"relative look moved");}
    if(index==5){Save(@"relative look stationary");[Controller handleTouchEndedAtPoint:CGPointMake(625,410) index:5];[Controller handleTouchEndedAtPoint:CGPointMake(230,375) index:4];
        for(unsigned i=1;i<=3;i++)[Controller handleTouchEndedAtPoint:CGPointMake(i*100,100) index:i];}
    if(index==6){Save(@"all released");return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{Step(index+1);});
}
@interface CPBackendScene:UIResponder<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation CPBackendScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];self.window.rootViewController=[UIViewController new];
    self.window.rootViewController.view.backgroundColor=UIColor.blackColor;[self.window makeKeyAndVisible];
    Samples=[NSMutableArray new];
    if(!TCTouchController.supported){SnapshotProbe();return;}
    TCTouchControllerDescriptor *descriptor=[TCTouchControllerDescriptor new];descriptor.device=MTLCreateSystemDefaultDevice();
    descriptor.size=CGSizeMake(1024,1024);descriptor.drawableSize=descriptor.size;descriptor.colorPixelFormat=MTLPixelFormatBGRA8Unorm;descriptor.sampleCount=1;
    Controller=[[TCTouchController alloc] initWithDescriptor:descriptor];
    NSArray *labels=@[TCControlLabel.buttonA,TCControlLabel.leftThumbstickButton,TCControlLabel.rightThumbstickButton,TCControlLabel.buttonMenu,TCControlLabel.buttonOptions];
    for(unsigned i=0;i<labels.count;i++) {
        TCButtonDescriptor *d=[TCButtonDescriptor new];d.label=labels[i];d.anchor=TCControlLayoutAnchorTopLeft;d.anchorCoordinateSystem=TCControlLayoutAnchorCoordinateSystemAbsolute;
        d.offset=CGPointMake(100*(i+1),100);d.size=CGSizeMake(70,70);d.colliderShape=TCColliderShapeRect;d.contents=nil;[Controller addButtonWithDescriptor:d];
    }
    TCThumbstickDescriptor *left=[TCThumbstickDescriptor new];left.label=TCControlLabel.leftThumbstick;
    left.anchor=TCControlLayoutAnchorTopLeft;left.anchorCoordinateSystem=TCControlLayoutAnchorCoordinateSystemAbsolute;left.offset=CGPointMake(200,400);left.size=CGSizeMake(100,100);left.colliderShape=TCColliderShapeCircle;[Controller addThumbstickWithDescriptor:left];
    TCTouchpadDescriptor *right=[TCTouchpadDescriptor new];right.label=TCControlLabel.rightThumbstick;
    right.anchor=TCControlLayoutAnchorTopLeft;right.anchorCoordinateSystem=TCControlLayoutAnchorCoordinateSystemAbsolute;right.offset=CGPointMake(600,400);right.size=CGSizeMake(200,200);right.colliderShape=TCColliderShapeRect;right.reportsRelativeValues=YES;[Controller addTouchpadWithDescriptor:right];
    [Controller connect];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{Step(0);});
}
@end
@interface CPBackendDelegate:UIResponder<UIApplicationDelegate> @end
@implementation CPBackendDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *c=[[UISceneConfiguration alloc] initWithName:@"Backend" sessionRole:session.role];c.delegateClass=CPBackendScene.class;return c;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(CPBackendDelegate.class));}}
