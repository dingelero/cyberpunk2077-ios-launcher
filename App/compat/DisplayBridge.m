// Adapted from Stray-iOS (c) 2026 xzk49, MIT. See AppKitThirdParty.LICENSE.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "AppKitBridge.h"
#import "DisplayPolicy.h"
#import "TouchControls.h"
#include <stdatomic.h>
#include <stdint.h>
#include <unistd.h>

const CFStringRef kCGDisplayShowDuplicateLowResolutionModes=CFSTR("kCGDisplayShowDuplicateLowResolutionModes");
static BOOL CursorVisible=YES;
static atomic_bool CursorAssociated=true;
static CGPoint CursorPoint;
static NSMutableArray *ReconfigurationCallbacks;
static NSMutableDictionary *FadeReservations;
static uint32_t NextFadeToken=1;
static NSDictionary *SelectedRenderingMode;
static void Main(void (^block)(void)){if(NSThread.isMainThread)block();else dispatch_sync(dispatch_get_main_queue(),block);}
static UIScreen *Screen(uint32_t display) { return display==1?(CPAppKitHostWindow().screen?:UIScreen.mainScreen):nil; }
static CGSize PixelSize(void){return [CPAppKitScreenGeometry()[@"pixelSize"] CGSizeValue];}
static NSDictionary *DisplayMode(void){NSDictionary *geometry=CPAppKitScreenGeometry();CGSize size=[geometry[@"pixelSize"] CGSizeValue];
    return @{@"width":@(size.width),@"height":@(size.height),@"refresh":geometry[@"maximumFPS"],@"scale":geometry[@"scale"]};}
static NSArray *RenderingModes(void) {
    // UIKit keeps the panel timing fixed. These are app render-target sizes,
    // displayed by the native CAMetalLayer using the current host aspect ratio.
    NSDictionary *geometry=CPAppKitScreenGeometry();double refresh=[geometry[@"maximumFPS"] doubleValue];
    CGSize full=CPFullScreenRenderSize([geometry[@"frame"] CGRectValue].size,720);
    CGSize full1080=CPFullScreenRenderSize([geometry[@"frame"] CGRectValue].size,1080);
    return @[@{@"width":@1280,@"height":@720,@"refresh":@(refresh),@"scale":@1,@"appRenderingMode":@YES},
             @{@"width":@(full.width),@"height":@(full.height),@"refresh":@(refresh),@"scale":@1,@"appRenderingMode":@YES},
             @{@"width":@1920,@"height":@1080,@"refresh":@(refresh),@"scale":@1,@"appRenderingMode":@YES},
             @{@"width":@(full1080.width),@"height":@(full1080.height),@"refresh":@(refresh),@"scale":@1,@"appRenderingMode":@YES}];
}
uint32_t CGMainDisplayID(void){return 1;}
CGRect CGDisplayBounds(uint32_t display){return display==1?[CPAppKitScreenGeometry()[@"frame"] CGRectValue]:CGRectZero;}
size_t CGDisplayPixelsWide(uint32_t display){return display==1?(size_t)PixelSize().width:0;}
size_t CGDisplayPixelsHigh(uint32_t display){return display==1?(size_t)PixelSize().height:0;}
CGSize CGDisplayScreenSize(uint32_t display){return CGSizeZero;} // Physical millimetres are not exposed by UIScreen.
uint32_t CGDisplayVendorNumber(uint32_t display){return 0;} // Unknown, not a fabricated hardware identifier.
uint32_t CGDisplayModelNumber(uint32_t display){return 0;}
uint32_t CGDisplaySerialNumber(uint32_t display){return 0;}
uint32_t CGDisplayIOServicePort(uint32_t display){return 0;} // No desktop IOKit display service exists in the app sandbox.
bool CGDisplayIsBuiltin(uint32_t display){return display==1;}
bool CGDisplayIsInMirrorSet(uint32_t display){return false;}
int32_t CGGetActiveDisplayList(uint32_t maximum,uint32_t *displays,uint32_t *count){if(!count)return 1001;*count=displays?MIN(maximum,1):1;if(displays&&maximum)displays[0]=1;return 0;}
void *CGDisplayCopyDisplayMode(uint32_t display){if(display!=1)return NULL;NSDictionary *selected;@synchronized(ReconfigurationCallbacks){selected=SelectedRenderingMode;}return (void *)CFBridgingRetain(selected ?: DisplayMode());}
CFArrayRef CGDisplayCopyAllDisplayModes(uint32_t display,CFDictionaryRef options){
    if(display!=1)return NULL;
    NSMutableArray *modes=[CPAppKitScreenGeometry()[@"availableModes"] mutableCopy];
    [modes addObjectsFromArray:RenderingModes()];return CFBridgingRetain(modes);
}
size_t CGDisplayModeGetWidth(void *mode){NSDictionary *d=(__bridge NSDictionary *)mode;double scale=[d[@"scale"] doubleValue];return (size_t)([d[@"width"] doubleValue]/MAX(1,scale));}
size_t CGDisplayModeGetHeight(void *mode){NSDictionary *d=(__bridge NSDictionary *)mode;double scale=[d[@"scale"] doubleValue];return (size_t)([d[@"height"] doubleValue]/MAX(1,scale));}
size_t CGDisplayModeGetPixelWidth(void *mode){return [((__bridge NSDictionary *)mode)[@"width"] unsignedLongValue];}
size_t CGDisplayModeGetPixelHeight(void *mode){return [((__bridge NSDictionary *)mode)[@"height"] unsignedLongValue];}
double CGDisplayModeGetRefreshRate(void *mode){return [((__bridge NSDictionary *)mode)[@"refresh"] doubleValue];}
uint32_t CGDisplayModeGetIOFlags(void *mode){return mode?3:0;} // valid and safe current UIKit display mode.
bool CGDisplayModeIsUsableForDesktopGUI(void *mode){return mode!=NULL;}
void *CGDisplayModeRetain(void *mode){if(mode)CFRetain(mode);return mode;}
void CGDisplayModeRelease(void *mode){if(mode)CFRelease(mode);}
int32_t CGDisplaySetDisplayMode(uint32_t display,void *mode,CFDictionaryRef options){
    if(display!=1 || !mode)return 1001;
    NSDictionary *value=(__bridge NSDictionary *)mode;
    if([RenderingModes() containsObject:value]) {
        @synchronized(ReconfigurationCallbacks){SelectedRenderingMode=[value copy];}
        NSLog(@"CP_DISPLAY app_rendering_mode %@ native_panel_timing_unchanged",value);
        return 0;
    }
    return [(__bridge NSDictionary *)mode isEqual:DisplayMode()]?0:1008; // iOS arbitrary timing changes are unavailable.
}
typedef void (*DisplayCallback)(uint32_t,uint32_t,void *);
int32_t CGDisplayRegisterReconfigurationCallback(DisplayCallback callback,void *context){if(!callback)return 1001;@synchronized(ReconfigurationCallbacks){[ReconfigurationCallbacks addObject:@[[NSValue valueWithPointer:callback],[NSValue valueWithPointer:context]]];}return 0;}
int32_t CGDisplayRemoveReconfigurationCallback(DisplayCallback callback,void *context){@synchronized(ReconfigurationCallbacks){NSIndexSet *indexes=[ReconfigurationCallbacks indexesOfObjectsPassingTest:^BOOL(NSArray *v,NSUInteger i,BOOL *stop){return [v[0] pointerValue]==callback && [v[1] pointerValue]==context;}];[ReconfigurationCallbacks removeObjectsAtIndexes:indexes];}return 0;}
BOOL CPAppKitPointerCaptured(void){return !atomic_load(&CursorAssociated);}
int32_t CGAssociateMouseAndMouseCursorPosition(bool associated){
    bool previous=atomic_exchange(&CursorAssociated,associated);
    if(previous!=associated)CPTouchControlsPointerCaptureChanged();return 0;
}
bool CGCursorIsVisible(void){return CursorVisible;}
int32_t CGDisplayHideCursor(uint32_t display){if(display!=1)return 1001;CursorVisible=NO;return 0;}
int32_t CGDisplayShowCursor(uint32_t display){if(display!=1)return 1001;CursorVisible=YES;return 0;}
int32_t CGWarpMouseCursorPosition(CGPoint point){CursorPoint=point;NSLog(@"CP_DISPLAY logical_cursor_warp %.3f %.3f",point.x,point.y);return 0;} // Local cursor, not system-wide pointer injection.
void *CGEventSourceCreate(int32_t state){return (void *)CFBridgingRetain([@{@"state":@(state),@"local_suppression":@0} mutableCopy]);}
void CGEventSourceSetLocalEventsSuppressionInterval(void *source,double interval){
    if(source)[(__bridge NSMutableDictionary *)source setObject:@(MAX(0,interval)) forKey:@"local_suppression"];
    NSLog(@"CP_DISPLAY local_event_source_suppression %.3f (no global event suppression on iOS)",interval);
}
CFDictionaryRef CGSessionCopyCurrentDictionary(void){return CFBridgingRetain(@{@"kCGSessionUserIDKey":@(getuid())});}
int32_t CGAcquireDisplayFadeReservation(float seconds,uint32_t *token){if(!token || seconds<=0 || seconds>15)return 1001;__block UIView *view;Main(^{view=[UIView new];});@synchronized(FadeReservations){*token=NextFadeToken++;FadeReservations[@(*token)]=view;}return 0;}
int32_t CGDisplayFade(uint32_t token,float duration,float start,float end,float red,float green,float blue,uint32_t synchronous){
    UIView *overlay;@synchronized(FadeReservations){overlay=FadeReservations[@(token)];}if(!overlay)return 1001;
    __block BOOL completed=NO;__block BOOL attached=NO;Main(^{UIWindow *window=NSApp.keyWindow.nativeWindow?:CPAppKitHostWindow();if(!window)return;
        attached=YES;overlay.frame=window.bounds;overlay.backgroundColor=[UIColor colorWithRed:red green:green blue:blue alpha:1];overlay.userInteractionEnabled=NO;
        overlay.alpha=start;[window addSubview:overlay];[UIView animateWithDuration:MAX(0,duration) animations:^{overlay.alpha=end;} completion:^(BOOL finished){completed=YES;}];});
    if(!attached)return 1008;
    if(synchronous)while(!completed){if(NSThread.isMainThread)[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];else[NSThread sleepForTimeInterval:0.01];}return 0;
}
int32_t CGReleaseDisplayFadeReservation(uint32_t token){UIView *view;@synchronized(FadeReservations){view=FadeReservations[@(token)];[FadeReservations removeObjectForKey:@(token)];}if(!view)return 1001;Main(^{[view removeFromSuperview];});return 0;}
__attribute__((constructor))static void SetupDisplay(void){ReconfigurationCallbacks=[NSMutableArray new];FadeReservations=[NSMutableDictionary new];
    [NSNotificationCenter.defaultCenter addObserverForName:UIScreenModeDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){NSArray *callbacks;@synchronized(ReconfigurationCallbacks){callbacks=[ReconfigurationCallbacks copy];}for(NSArray *entry in callbacks){DisplayCallback callback=[entry[0] pointerValue];callback(1,1<<8,[entry[1] pointerValue]);}}];
}
