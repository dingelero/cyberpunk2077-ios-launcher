// Adapted from Stray-iOS (c) 2026 xzk49, MIT license.
// Full notice: AppKitThirdParty.LICENSE. Cyberpunk-specific adaptation.
#import "AppKitBridge.h"
#include <math.h>
#import "CoalescedUpdate.h"
#import "TouchControls.h"
#import <Metal/Metal.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <unistd.h>
#import <os/lock.h>

#include "AppKitConstants.inc"
NSApplication *NSApp;
static __weak UIWindow *HostWindow;
static NSMutableDictionary *Runtime;
static NSMutableArray *Monitors;
static CGPoint MouseLocation;
static NSUInteger MouseButtons;
static NSUInteger ModifierFlags;
static BOOL ApplicationActive=YES;
static BOOL GuestStopped;
static NSMutableArray *PausedDisplayLinks;
static os_unfair_lock ScreenGeometryLock=OS_UNFAIR_LOCK_INIT;
static NSDictionary *ScreenGeometry;
static void RefreshScreenGeometry(void) {
    NSCAssert(NSThread.isMainThread,@"Native screen geometry must be read on UIKit's thread");
    UIScreen *screen=HostWindow.screen?:UIScreen.mainScreen;
    NSMutableArray *modes=[NSMutableArray new];
    for(UIScreenMode *mode in screen.availableModes)
        [modes addObject:@{@"width":@(mode.size.width),@"height":@(mode.size.height),
            @"refresh":@(screen.maximumFramesPerSecond),@"scale":@(screen.scale)}];
    NSDictionary *value=@{@"frame":[NSValue valueWithCGRect:screen.bounds],@"scale":@(screen.scale),
        @"pixelSize":[NSValue valueWithCGSize:screen.currentMode.size],@"availableModes":modes,
        @"maximumFPS":@(screen.maximumFramesPerSecond),@"description":@{@"NSScreenNumber":@1,
        @"NSDeviceSize":[NSValue valueWithCGSize:screen.bounds.size],@"NSDeviceResolution":[NSValue valueWithCGSize:CGSizeMake(72,72)]}};
    os_unfair_lock_lock(&ScreenGeometryLock);ScreenGeometry=value;os_unfair_lock_unlock(&ScreenGeometryLock);
}
static NSDictionary *NativeScreenGeometry(void) {
    os_unfair_lock_lock(&ScreenGeometryLock);NSDictionary *value=ScreenGeometry;os_unfair_lock_unlock(&ScreenGeometryLock);
    if(!value) {
        if(NSThread.isMainThread)RefreshScreenGeometry();else dispatch_sync(dispatch_get_main_queue(),^{RefreshScreenGeometry();});
        os_unfair_lock_lock(&ScreenGeometryLock);value=ScreenGeometry;os_unfair_lock_unlock(&ScreenGeometryLock);
    }
    return value;
}
NSDictionary *CPAppKitScreenGeometry(void) { return NativeScreenGeometry(); }
static BOOL HDRRequested(void) {const char *value=getenv("CP2077_HDR_REQUESTED");return value && !strcmp(value,"1");}
static void Invoke(id target, NSString *selectorName, id argument) {
    SEL selector=NSSelectorFromString(selectorName);
    if([target respondsToSelector:selector])((void(*)(id,SEL,id))objc_msgSend)(target,selector,argument);
}
static void WindowNotice(NSWindow *window, NSString *name, NSString *selector) {
    if(GuestStopped)return;
    NSNotification *notice=[NSNotification notificationWithName:name object:window];
    [NSNotificationCenter.defaultCenter postNotification:notice];
    Invoke(window.delegate,selector,notice);
}

static void Main(void (^block)(void)) {
    if (NSThread.isMainThread) block(); else dispatch_sync(dispatch_get_main_queue(), block);
}
static void Note(NSString *name, id value) {
    @synchronized(Runtime) { Runtime[name] = value; }
    NSLog(@"CP_APPKIT %@ %@", name, value);
}
void CPAppKitBindHostWindow(UIWindow *window) { Main(^{HostWindow = window;RefreshScreenGeometry();}); Note(@"host_window_bound",@(window!=nil)); }
UIWindow *CPAppKitHostWindow(void) { return HostWindow; }
void CPAppKitSetApplicationActive(BOOL active) {
    Main(^{
        if(GuestStopped)return;
        RefreshScreenGeometry();
        if(ApplicationActive==active)return;
        ApplicationActive=active;
        NSString *name=active?NSApplicationDidBecomeActiveNotification:NSApplicationWillResignActiveNotification;
        NSNotification *notice=[NSNotification notificationWithName:name object:NSApp];
        [NSNotificationCenter.defaultCenter postNotification:notice];
        Invoke(NSApp.delegate,active?@"applicationDidBecomeActive:":@"applicationWillResignActive:",notice);
        if(!active) {
            [PausedDisplayLinks removeAllObjects];
            for(NSWindow *window in NSApp.windows) {
                id view=window.contentView;
                SEL getter=NSSelectorFromString(@"getMetaleDisplayLink");
                NSMethodSignature *signature=[view methodSignatureForSelector:getter];
                const char *image=class_getImageName(object_getClass(view));
                BOOL validated=signature && signature.numberOfArguments==2 && signature.methodReturnType[0]=='@' && image && strstr(image,"CyberpunkGuest");
                id link=validated?((id(*)(id,SEL))objc_msgSend)(view,getter):nil;
                if(!link) {getter=NSSelectorFromString(@"m_displayLink");signature=[view methodSignatureForSelector:getter];
                    if(signature && signature.numberOfArguments==2 && signature.methodReturnType[0]=='@' && image && strstr(image,"CyberpunkGuest"))link=((id(*)(id,SEL))objc_msgSend)(view,getter);}
                if(link)Note(@"lifecycle_display_link_class",NSStringFromClass([link class]));
                SEL setter=NSSelectorFromString(@"setPaused:");
                SEL read=NSSelectorFromString(@"isPaused");
                if(link && [link respondsToSelector:setter]) {
                    BOOL already=[link respondsToSelector:read]?((BOOL(*)(id,SEL))objc_msgSend)(link,read):NO;
                    if(!already){((void(*)(id,SEL,BOOL))objc_msgSend)(link,setter,YES);[PausedDisplayLinks addObject:link];}
                }
                if(window==NSApp.keyWindow)WindowNotice(window,NSWindowDidResignKeyNotification,@"windowDidResignKey:");
            }
            NSNotification *did=[NSNotification notificationWithName:NSApplicationDidResignActiveNotification object:NSApp];
            [NSNotificationCenter.defaultCenter postNotification:did];Invoke(NSApp.delegate,@"applicationDidResignActive:",did);
        } else {
            for(id link in PausedDisplayLinks)((void(*)(id,SEL,BOOL))objc_msgSend)(link,NSSelectorFromString(@"setPaused:"),NO);
            [PausedDisplayLinks removeAllObjects];
            if(NSApp.keyWindow)WindowNotice(NSApp.keyWindow,NSWindowDidBecomeKeyNotification,@"windowDidBecomeKey:");
        }
        Note(@"application_active",@(active));Note(@"lifecycle_paused_display_links",@(PausedDisplayLinks.count));
    });
}
void CPAppKitGuestStopped(void) {
    CPTouchControlsGuestStopped();
    Main(^{
        GuestStopped=YES;
        [NSNotificationCenter.defaultCenter removeObserver:NSApp.delegate];NSApp.delegate=nil;
        for(NSWindow *window in NSApp.windows){[NSNotificationCenter.defaultCenter removeObserver:window.delegate];window.delegate=nil;}
        [PausedDisplayLinks removeAllObjects];
        Note(@"guest_stopped",@YES);
    });
}
NSDictionary *CPAppKitRuntimeReport(void) {
    NSMutableDictionary *report;
    @synchronized(Runtime) { report=[Runtime mutableCopy]; }
    __block NSMutableArray *windows=[NSMutableArray new];
    Main(^{
        for(NSWindow *window in [NSApp.windows copy]) {
            NSView *view=window.contentView; CALayer *layer=view.layer;
            CAMetalLayer *metal=[layer isKindOfClass:CAMetalLayer.class]?(CAMetalLayer *)layer:nil;
            [windows addObject:@{ @"windowNumber":@(window.windowNumber), @"windowVisible":@(window.visible),
                @"nativeWindowHidden":@(window.nativeWindow.hidden), @"nativeWindowKey":@(window.nativeWindow.isKeyWindow),
                @"viewClass":NSStringFromClass(view.class) ?: @"none", @"viewAttachedToWindow":@(view.nativeView.window==window.nativeWindow),
                @"nativeViewBounds":NSStringFromCGRect(view.nativeView.bounds), @"nativeViewHidden":@(view.nativeView.hidden),
                @"layerAttachedToNativeView":@(layer && layer.superlayer==view.nativeView.layer),
                @"layerHidden":@(layer.hidden), @"layerOpacity":@(layer.opacity), @"layerFrame":NSStringFromCGRect(layer.frame),
                @"metalLayer":@(metal!=nil), @"drawableSize":metal?NSStringFromCGSize(metal.drawableSize):@"none",
                @"metalPixelFormat":metal?@(metal.pixelFormat):@0,
                @"metalColorSpace":(metal.colorspace?(__bridge_transfer NSString *)CGColorSpaceCopyName(metal.colorspace):nil) ?: @"none",
                @"presentsWithTransaction":@(metal.presentsWithTransaction),
                @"wantsExtendedDynamicRangeContent":@(metal.wantsExtendedDynamicRangeContent),
                @"screenCurrentEDRHeadroom":@(window.nativeWindow.screen.currentEDRHeadroom),
                @"screenPotentialEDRHeadroom":@(window.nativeWindow.screen.potentialEDRHeadroom),
                @"nativeSceneActivationState":@(window.nativeWindow.windowScene.activationState) }];
        }
    });
    report[@"nativeWindowPresentation"]=windows;
    Main(^{report[@"touchControls"]=CPTouchControlsReport();});
    return report;
}

@interface CPCanvas : UIView
@property(nonatomic, weak) NSView *cocoaView;
@property(nonatomic) CGPoint lastTouch;
@end
@implementation CPCanvas
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)layoutSubviews {
    [super layoutSubviews];
    // UIKit owns rotation/mode changes. Publish native geometry when layout
    // changes instead of blocking rendering workers for each screen getter.
    RefreshScreenGeometry();
    CALayer *layer=self.cocoaView.layer;
    if(!layer)return;
    CGRect viewport=self.bounds;
    if([layer isKindOfClass:CAMetalLayer.class]){
        CGSize image=((CAMetalLayer *)layer).drawableSize;
        if(!image.width || !image.height)image=self.cocoaView.bounds.size;
        if(image.width>0 && image.height>0 && fabs(image.width/image.height-viewport.size.width/viewport.size.height)>0.005){
            CGFloat scale=MIN(viewport.size.width/image.width,viewport.size.height/image.height);
            CGSize size=CGSizeMake(image.width*scale,image.height*scale);
            viewport=CGRectMake(CGRectGetMidX(self.bounds)-size.width/2,CGRectGetMidY(self.bounds)-size.height/2,size.width,size.height);
        }
    }
    if(!CGRectEqualToRect(layer.frame,viewport)) {
        [CATransaction begin];[CATransaction setDisableActions:YES];layer.frame=viewport;[CATransaction commit];
    }
}
- (void)emitTouch:(UITouch *)touch type:(NSUInteger)type {
    NSWindow *window = self.cocoaView.window;
    if (!window) return;
    CGPoint p = [touch locationInView:self];
    CGRect viewport=[self.cocoaView.layer isKindOfClass:CAMetalLayer.class]?self.cocoaView.layer.frame:self.bounds;
    if(type==1 && !CGRectContainsPoint(viewport,p))return;
    p.x-=viewport.origin.x;p.y-=viewport.origin.y;
    CGFloat sx = viewport.size.width ? self.cocoaView.bounds.size.width / viewport.size.width : 1;
    CGFloat sy = viewport.size.height ? self.cocoaView.bounds.size.height / viewport.size.height : 1;
    NSEvent *event = [NSEvent new];
    event.type = type; event.windowNumber = window.windowNumber;
    event.locationInWindow = CGPointMake(p.x * sx, self.cocoaView.bounds.size.height - p.y * sy);
    event.timestamp = touch.timestamp; event.clickCount = touch.tapCount;
    event.deltaX = (p.x - self.lastTouch.x) * sx; event.deltaY = (p.y - self.lastTouch.y) * sy;
    self.lastTouch = p; MouseLocation = event.locationInWindow;
    MouseButtons = type == 2 ? 0 : 1;
    [NSApp postEvent:event atStart:NO];
}
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event { [self becomeFirstResponder]; [self emitTouch:touches.anyObject type:1]; }
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event { [self emitTouch:touches.anyObject type:6]; }
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event { [self emitTouch:touches.anyObject type:2]; }
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event { [self emitTouch:touches.anyObject type:2]; }
- (void)emitPresses:(NSSet<UIPress *> *)presses down:(BOOL)down {
    NSDictionary *codes = @{@"a":@0,@"s":@1,@"d":@2,@"f":@3,@"h":@4,@"g":@5,@"z":@6,@"x":@7,
        @"c":@8,@"v":@9,@"b":@11,@"q":@12,@"w":@13,@"e":@14,@"r":@15,@"y":@16,@"t":@17,
        @"1":@18,@"2":@19,@"3":@20,@"4":@21,@"6":@22,@"5":@23,@"9":@25,@"7":@26,@"8":@28,@"0":@29,
        @"o":@31,@"u":@32,@"i":@34,@"p":@35,@"l":@37,@"j":@38,@"k":@40,@"n":@45,@"m":@46,@" ":@49};
    for (UIPress *press in presses) {
        UIKey *key = press.key; if (!key) continue;
        NSNumber *code = codes[key.charactersIgnoringModifiers.lowercaseString];
        switch (key.keyCode) {
            case UIKeyboardHIDUsageKeyboardReturnOrEnter: code=@36; break;
            case UIKeyboardHIDUsageKeyboardEscape: code=@53; break;
            case UIKeyboardHIDUsageKeyboardDeleteOrBackspace: code=@51; break;
            case UIKeyboardHIDUsageKeyboardTab: code=@48; break;
            case UIKeyboardHIDUsageKeyboardLeftArrow: code=@123; break;
            case UIKeyboardHIDUsageKeyboardRightArrow: code=@124; break;
            case UIKeyboardHIDUsageKeyboardDownArrow: code=@125; break;
            case UIKeyboardHIDUsageKeyboardUpArrow: code=@126; break;
            default: break;
        }
        if (!code) continue;
        NSEvent *event = [NSEvent new]; event.type = down ? 10 : 11; event.keyCode = code.unsignedShortValue;
        event.characters=key.characters; event.charactersIgnoringModifiers=key.charactersIgnoringModifiers;
        event.modifierFlags=key.modifierFlags; ModifierFlags=event.modifierFlags;
        event.timestamp=NSProcessInfo.processInfo.systemUptime; event.windowNumber=self.cocoaView.window.windowNumber;
        [NSApp postEvent:event atStart:NO];
    }
}
- (void)pressesBegan:(NSSet *)presses withEvent:(UIPressesEvent *)event { [self emitPresses:presses down:YES]; }
- (void)pressesEnded:(NSSet *)presses withEvent:(UIPressesEvent *)event { [self emitPresses:presses down:NO]; }
@end

@implementation NSView
- (BOOL)inLiveResize { return NO; } // UIKit fullscreen views have no AppKit resize-drag session.
- (instancetype)init { return [self initWithFrame:CGRectZero]; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super init])) {
        _frame=frame; _bounds=(CGRect){CGPointZero,frame.size}; _subviews=[NSMutableArray new];_trackingAreas=[NSMutableArray new];
        Main(^{ CPCanvas *view=[[CPCanvas alloc] initWithFrame:frame]; view.cocoaView=self;
            view.backgroundColor=UIColor.blackColor; self.nativeView=view; });
    }
    return self;
}
- (CALayer *)makeBackingLayer { __block CALayer *layer;Main(^{layer=[CALayer layer];});return layer; }
- (void)setWantsLayer:(BOOL)value { _wantsLayer=value; if(value && !_layer) [self setLayer:[self makeBackingLayer]]; }
- (void)setLayer:(CALayer *)layer {
    if([layer isKindOfClass:CAMetalLayer.class])layer.name=@"CPGuestMetalLayer";
    Main(^{ [self->_layer removeFromSuperlayer]; self->_layer=layer;
        layer.frame=self.nativeView.bounds; layer.contentsScale=UIScreen.mainScreen.scale;
        [self.nativeView.layer addSublayer:layer];[self.nativeView setNeedsLayout]; });
    if([layer isKindOfClass:CAMetalLayer.class] && HDRRequested())self->_wantsExtendedDynamicRangeContent=YES;
    if(self.wantsExtendedDynamicRangeContent)[self setWantsExtendedDynamicRangeContent:YES];
    Note(@"layer_class",layer?NSStringFromClass(layer.class):@"nil");
}
- (void)setFrame:(CGRect)frame {
    _frame=frame; _bounds.size=frame.size;
    Main(^{ self.nativeView.frame=frame; self.layer.frame=self.nativeView.bounds; });
    if (_postsFrameChangedNotifications) [NSNotificationCenter.defaultCenter postNotificationName:NSViewFrameDidChangeNotification object:self];
}
- (void)setFrameSize:(CGSize)size { [self setFrame:(CGRect){_frame.origin,size}]; }
- (void)setFrameOrigin:(CGPoint)origin { [self setFrame:(CGRect){origin,_frame.size}]; }
- (void)setBounds:(CGRect)bounds { _bounds=bounds; if(_postsBoundsChangedNotifications) [NSNotificationCenter.defaultCenter postNotificationName:NSViewBoundsDidChangeNotification object:self]; }
- (void)setBoundsSize:(CGSize)size { self.bounds=(CGRect){_bounds.origin,size}; }
- (void)setHidden:(BOOL)hidden { _hidden=hidden; Main(^{self.nativeView.hidden=hidden;}); }
- (BOOL)isHidden { return _hidden; }
- (BOOL)isFlipped { return NO; }
- (BOOL)isOpaque { __block BOOL value;Main(^{value=self.nativeView.opaque;});return value; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder { __block BOOL value;Main(^{value=[self.nativeView becomeFirstResponder];}); return value; }
- (BOOL)resignFirstResponder { __block BOOL value;Main(^{value=[self.nativeView resignFirstResponder];}); return value; }
- (void)setWindow:(NSWindow *)window { _window=window; for(NSView *v in self.subviews)v.window=window; }
- (void)addSubview:(NSView *)view { [view removeFromSuperview]; [_subviews addObject:view]; view.superview=self; view.window=self.window;
    Main(^{[self.nativeView addSubview:view.nativeView];}); }
- (void)removeFromSuperview { [self.superview.subviews removeObject:self]; self.superview=nil; Main(^{[self.nativeView removeFromSuperview];}); }
- (CGRect)convertRect:(CGRect)rect toView:(NSView *)view { __block CGRect result; Main(^{result=[self.nativeView convertRect:rect toView:view.nativeView];});return result; }
- (CGRect)convertRect:(CGRect)rect fromView:(NSView *)view { __block CGRect result; Main(^{result=[self.nativeView convertRect:rect fromView:view.nativeView];});return result; }
- (CGPoint)convertPoint:(CGPoint)point toView:(NSView *)view { return [self convertRect:(CGRect){point,CGSizeZero} toView:view].origin; }
- (CGPoint)convertPoint:(CGPoint)point fromView:(NSView *)view { return [self convertRect:(CGRect){point,CGSizeZero} fromView:view].origin; }
- (CGRect)convertRectToBacking:(CGRect)rect { CGFloat s=self.window.backingScaleFactor; return CGRectMake(rect.origin.x*s,rect.origin.y*s,rect.size.width*s,rect.size.height*s); }
- (CGRect)convertRectFromBacking:(CGRect)rect { CGFloat s=self.window.backingScaleFactor?:1; return CGRectMake(rect.origin.x/s,rect.origin.y/s,rect.size.width/s,rect.size.height/s); }
- (void)setNeedsDisplay:(BOOL)display { Main(^{if(display)[self.nativeView setNeedsDisplay];}); }
- (void)display { Main(^{[self.nativeView.layer displayIfNeeded];}); }
- (void)displayIfNeeded { [self display]; }
- (void)registerForDraggedTypes:(NSArray *)types { Note(@"drag_types_unavailable",types?:@[]); }
- (void)unregisterDraggedTypes {}
- (void)addTrackingArea:(NSTrackingArea *)area { if(area)[self.trackingAreas addObject:area]; }
- (void)removeTrackingArea:(NSTrackingArea *)area { [self.trackingAreas removeObject:area]; }
- (void)updateTrackingAreas {} // Tracking ownership is maintained; pointer events enter via UIKit.
- (void)addCursorRect:(CGRect)rect cursor:(id)cursor {}
- (void)resetCursorRects {}
- (void)discardCursorRects {}
- (void)layout { Main(^{[self.nativeView setNeedsLayout];[self.nativeView layoutIfNeeded];}); }
- (CGRect)visibleRect { return self.bounds; }
- (void)setWantsExtendedDynamicRangeContent:(BOOL)enabled {
    _wantsExtendedDynamicRangeContent=enabled;
    Main(^{SEL selector=NSSelectorFromString(@"setWantsExtendedDynamicRangeContent:");
        if([self.layer respondsToSelector:selector])((void(*)(id,SEL,BOOL))objc_msgSend)(self.layer,selector,enabled);
        // The real Metal layer now owns the EDR request; retire startup's
        // temporary UIKit request so an in-game SDR switch can save power.
        if(self.nativeView.window)self.nativeView.window.rootViewController.view.layer.wantsExtendedDynamicRangeContent=NO;
        [CATransaction flush];});
}
- (void)rightMouseDown:(id)event {}
- (void)rightMouseUp:(id)event {}
- (void)rightMouseDragged:(id)event {}
- (void)otherMouseDown:(id)event {}
- (void)otherMouseUp:(id)event {}
- (void)otherMouseDragged:(id)event {}
- (void)scrollWheel:(id)event {}
- (void)mouseEntered:(id)event {}
- (void)mouseExited:(id)event {}
- (void)viewWillMoveToWindow:(id)window {}
- (void)viewDidMoveToWindow {}
- (void)mouseDown:(id)event {}
- (void)mouseUp:(id)event {}
- (void)mouseMoved:(id)event {}
- (void)mouseDragged:(id)event {}
- (void)keyDown:(id)event {}
- (void)keyUp:(id)event {}
- (void)flagsChanged:(id)event {}
@end

@implementation NSScreen
+ (instancetype)mainScreen { static NSScreen *s; static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s; }
+ (NSArray *)screens { return @[[self mainScreen]]; }
- (CGRect)frame { return [NativeScreenGeometry()[@"frame"] CGRectValue]; }
- (CGRect)visibleFrame { return self.frame; }
- (CGFloat)backingScaleFactor { return [NativeScreenGeometry()[@"scale"] doubleValue]; }
- (NSDictionary *)deviceDescription { return NativeScreenGeometry()[@"description"]; }
- (NSInteger)maximumFramesPerSecond { return [NativeScreenGeometry()[@"maximumFPS"] integerValue]; }
- (NSTimeInterval)minimumRefreshInterval { return 1.0/MAX(1,self.maximumFramesPerSecond); }
- (NSTimeInterval)maximumRefreshInterval { return 1.0/30.0; }
- (CGRect)safeAreaRect { __block CGRect rect;Main(^{rect=HostWindow?UIEdgeInsetsInsetRect(HostWindow.bounds,HostWindow.safeAreaInsets):self.frame;});return rect; }
- (NSInteger)depth { return 32; }
- (CGFloat)maximumExtendedDynamicRangeColorComponentValue { __block CGFloat value;Main(^{value=(HostWindow.screen?:UIScreen.mainScreen).currentEDRHeadroom;});return value; }
- (CGFloat)maximumPotentialExtendedDynamicRangeColorComponentValue { __block CGFloat value;Main(^{value=(HostWindow.screen?:UIScreen.mainScreen).potentialEDRHeadroom;});return value; }
- (BOOL)canRepresentDisplayGamut:(NSInteger)gamut { return gamut<=1 || UIScreen.mainScreen.traitCollection.displayGamut==UIDisplayGamutP3; }
@end

@interface CPGameViewController : UIViewController @end
@implementation CPGameViewController
- (BOOL)prefersStatusBarHidden {return YES;}
- (BOOL)prefersHomeIndicatorAutoHidden {return YES;}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {return UIInterfaceOrientationMaskLandscape;}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {return UIInterfaceOrientationLandscapeRight;}
@end

@implementation NSWindow
- (void)disableSnapshotRestoration { self.restorable=NO; }
// The guest's local monitor already defers these events to its engine. Its text view
// also calls the window's default NSResponder endpoints for window ordering.
- (void)mouseDown:(NSEvent *)event { if(!self.isKeyWindow)[self makeKeyAndOrderFront:nil]; }
- (void)mouseUp:(NSEvent *)event {}
- (void)mouseDragged:(NSEvent *)event {}
- (void)mouseMoved:(NSEvent *)event {}
- (void)setIgnoresMouseEvents:(BOOL)ignore { _ignoresMouseEvents=ignore;Main(^{self.nativeWindow.userInteractionEnabled=!ignore;}); }
+ (NSInteger)windowNumberAtPoint:(CGPoint)point belowWindowWithWindowNumber:(NSInteger)number {
    BOOL below=number==0;
    for(NSWindow *window in [NSApp.windows reverseObjectEnumerator]){
        if(!below){if(window.windowNumber==number)below=YES;continue;}
        if(window.visible && !window.ignoresMouseEvents && CGRectContainsPoint(window.frame,point))return window.windowNumber;
    }
    return 0;
}
- (instancetype)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)style backing:(NSUInteger)backing defer:(BOOL)defer {
    if ((self=[super init])) {
        _frame=rect; _styleMask=style; _alphaValue=1; _minSize=CGSizeMake(1,1);_maxSize=CGSizeMake(CGFLOAT_MAX,CGFLOAT_MAX);
        _windowNumber=(NSInteger)NSApp.windows.count+1;
        Main(^{ UIWindow *w=NSApp.windows.count==0 && HostWindow?HostWindow:(HostWindow.windowScene?[[UIWindow alloc] initWithWindowScene:HostWindow.windowScene]:[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]);
            w.frame=UIScreen.mainScreen.bounds; w.rootViewController=[CPGameViewController new];w.rootViewController.view.backgroundColor=UIColor.blackColor;
            w.rootViewController.view.layer.wantsExtendedDynamicRangeContent=HDRRequested();[CATransaction flush];
            self.nativeWindow=w; });
        [NSApp.windows addObject:self];
        self.contentView=[[NSView alloc] initWithFrame:(CGRect){CGPointZero,rect.size}];
        Note(@"window_created",@YES);
    }
    return self;
}
- (instancetype)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)style backing:(NSUInteger)backing defer:(BOOL)defer screen:(NSScreen *)screen { return [self initWithContentRect:rect styleMask:style backing:backing defer:defer]; }
- (void)setContentView:(NSView *)view {
    Main(^{[self->_contentView.nativeView removeFromSuperview]; self->_contentView=view; view.window=self;
        view.nativeView.frame=self.nativeWindow.rootViewController.view.bounds;
        view.nativeView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        view.layer.frame=view.nativeView.bounds;
        [self.nativeWindow.rootViewController.view addSubview:view.nativeView];
        if(self.nativeWindow==HostWindow)CPAttachTouchControls(self.nativeWindow); });
}
- (NSScreen *)screen { return NSScreen.mainScreen; }
- (CGFloat)backingScaleFactor { return self.screen.backingScaleFactor; }
- (CGRect)frameRectForContentRect:(CGRect)rect { return rect; }
- (CGRect)contentRectForFrameRect:(CGRect)rect { return rect; }
- (CGRect)contentLayoutRect {
    // This full-screen bridge has no desktop titlebar or toolbar. AppKit defines
    // the layout rect in window coordinates, normally as contentView.frame.
    // Keep the guest's logical geometry; its native Metal viewport is separate.
    CGRect rect=self.contentView ? self.contentView.frame : (CGRect){CGPointZero,self.frame.size};
    static dispatch_once_t once;
    dispatch_once(&once, ^{ Note(@"content_layout_rect",NSStringFromCGRect(rect)); });
    return rect;
}
+ (CGRect)frameRectForContentRect:(CGRect)rect styleMask:(NSUInteger)style { return rect; }
- (void)setFrame:(CGRect)rect display:(BOOL)display { self.frame=rect;self.contentView.frame=(CGRect){CGPointZero,rect.size};
    Main(^{self.contentView.nativeView.frame=self.nativeWindow.rootViewController.view.bounds;self.contentView.layer.frame=self.contentView.nativeView.bounds;});
    WindowNotice(self,NSWindowDidResizeNotification,@"windowDidResize:"); }
- (void)setFrameOrigin:(CGPoint)origin { self.frame=(CGRect){origin,self.frame.size}; }
- (void)setContentSize:(CGSize)size { [self setFrame:(CGRect){self.frame.origin,size} display:YES]; }
- (void)orderFront:(id)sender { [self makeKeyAndOrderFront:sender]; }
- (void)setIsVisible:(BOOL)visible { if(visible)[self orderFront:nil];else[self orderOut:nil]; }
- (void)makeKeyAndOrderFront:(id)sender { NSWindow *old=NSApp.keyWindow;
    self.visible=YES;NSApp.keyWindow=self;NSApp.mainWindow=self;
    if(old && old!=self)WindowNotice(old,NSWindowDidResignKeyNotification,@"windowDidResignKey:");
    if(old!=self)WindowNotice(self,NSWindowDidBecomeKeyNotification,@"windowDidBecomeKey:");
    Main(^{[self.nativeWindow makeKeyAndVisible];[self.contentView.nativeView setNeedsLayout];[self.contentView.nativeView layoutIfNeeded];[self.contentView.nativeView becomeFirstResponder];
        Note(@"presentation_geometry",@{@"native":NSStringFromCGRect(self.contentView.nativeView.bounds),@"guest":NSStringFromCGRect(self.contentView.bounds),@"layer":NSStringFromCGRect(self.contentView.layer.frame)});});Note(@"window_visible",@YES); }
- (void)makeMainWindow { NSApp.mainWindow=self; }
- (void)makeKeyWindow { [self makeKeyAndOrderFront:nil]; }
- (void)orderWindow:(NSInteger)ordering relativeTo:(NSInteger)number { if(ordering<0)[self orderOut:nil];else[self orderFront:nil]; }
- (void)orderOut:(id)sender { self.visible=NO;Main(^{self.nativeWindow.hidden=YES;}); }
- (void)close { WindowNotice(self,NSWindowWillCloseNotification,@"windowWillClose:");[self orderOut:nil]; [NSApp.windows removeObject:self]; }
- (void)setFrame:(CGRect)rect display:(BOOL)display animate:(BOOL)animate { [self setFrame:rect display:display]; }
- (NSUInteger)occlusionState { return self.visible && ApplicationActive?(1UL<<1):0; }
- (void)performMiniaturize:(id)sender { [self miniaturize:sender]; }
- (void)invalidateCursorRectsForView:(NSView *)view { [view resetCursorRects]; }
- (void)toggleFullScreen:(id)sender {
    BOOL leaving=!!(self.styleMask&(1UL<<14));
    WindowNotice(self,leaving?NSWindowWillExitFullScreenNotification:NSWindowWillEnterFullScreenNotification,leaving?@"windowWillExitFullScreen:":@"windowWillEnterFullScreen:");
    self.styleMask=leaving?(self.styleMask&~(1UL<<14)):(self.styleMask|(1UL<<14));
    [self setFrame:self.screen.frame display:YES];
    WindowNotice(self,leaving?NSWindowDidExitFullScreenNotification:NSWindowDidEnterFullScreenNotification,leaving?@"windowDidExitFullScreen:":@"windowDidEnterFullScreen:");
}
- (BOOL)isVisible { return self.visible; }
- (BOOL)isKeyWindow { return NSApp.keyWindow==self; }
- (BOOL)isMainWindow { return NSApp.mainWindow==self; }
- (BOOL)isOnActiveSpace { return self.visible; }
- (BOOL)isZoomed { return self.zoomed; }
- (BOOL)isMiniaturized { return self.miniaturized; }
- (void)miniaturize:(id)sender { self.miniaturized=YES;[self orderOut:sender]; }
- (void)deminiaturize:(id)sender { self.miniaturized=NO;[self orderFront:sender]; }
- (void)zoom:(id)sender { self.zoomed=!self.zoomed;[self setFrame:self.screen.frame display:YES]; }
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
- (BOOL)makeFirstResponder:(id)responder { self.firstResponder=responder;Main(^{[self.contentView.nativeView becomeFirstResponder];});return YES; }
- (void)setAlphaValue:(CGFloat)value { _alphaValue=value;Main(^{self.nativeWindow.alpha=value;}); }
- (void)setBackgroundColor:(id)color { _backgroundColor=color; Main(^{if([color isKindOfClass:UIColor.class])self.nativeWindow.backgroundColor=color;}); }
- (id)standardWindowButton:(NSUInteger)button { return nil; } // iOS windows have no titlebar controls.
- (void)registerForDraggedTypes:(NSArray *)types { [self.contentView registerForDraggedTypes:types]; }
- (void)invalidateShadow {}
- (void)disableCursorRects {}
- (void)enableCursorRects {}
- (CGPoint)convertPointToScreen:(CGPoint)p { return CGPointMake(p.x+self.frame.origin.x,p.y+self.frame.origin.y); }
- (CGPoint)convertPointFromScreen:(CGPoint)p { return CGPointMake(p.x-self.frame.origin.x,p.y-self.frame.origin.y); }
- (CGRect)convertRectToScreen:(CGRect)r { r.origin=[self convertPointToScreen:r.origin];return r; }
- (CGRect)convertRectFromScreen:(CGRect)r { r.origin=[self convertPointFromScreen:r.origin];return r; }
- (CGRect)convertRectToBacking:(CGRect)r { return [self.contentView convertRectToBacking:r]; }
- (CGRect)convertRectFromBacking:(CGRect)r { return [self.contentView convertRectFromBacking:r]; }
- (CGPoint)mouseLocationOutsideOfEventStream { return MouseLocation; }
@end

@interface CPMonitor : NSObject
@property(nonatomic) uint64_t mask;
@property(nonatomic, copy) NSEvent *(^local)(NSEvent *);
@property(nonatomic, copy) void (^global)(NSEvent *);
@end
@implementation CPMonitor @end
@implementation NSEvent
- (NSWindow *)window { return [NSApp windowWithWindowNumber:self.windowNumber]; }
+ (id)addLocalMonitorForEventsMatchingMask:(uint64_t)mask handler:(NSEvent *(^)(NSEvent *))handler { CPMonitor *m=[CPMonitor new];m.mask=mask;m.local=handler;@synchronized(Monitors){[Monitors addObject:m];}return m; }
+ (id)addGlobalMonitorForEventsMatchingMask:(uint64_t)mask handler:(void (^)(NSEvent *))handler { CPMonitor *m=[CPMonitor new];m.mask=mask;m.global=handler;@synchronized(Monitors){[Monitors addObject:m];}return m; }
+ (void)removeMonitor:(id)monitor { @synchronized(Monitors){[Monitors removeObject:monitor];} }
+ (CGPoint)mouseLocation { return MouseLocation; }
+ (NSUInteger)pressedMouseButtons { return MouseButtons; }
+ (NSUInteger)modifierFlags { return ModifierFlags; }
+ (void)setMouseCoalescingEnabled:(BOOL)enabled { Note(@"mouse_coalescing",@(enabled)); }
- (BOOL)hasPreciseScrollingDeltas { return YES; }
- (BOOL)isDirectionInvertedFromDevice { return NO; }
- (float)pressure { return MouseButtons?1:0; }
+ (instancetype)otherEventWithType:(NSUInteger)type location:(CGPoint)point modifierFlags:(NSUInteger)flags timestamp:(NSTimeInterval)time windowNumber:(NSInteger)number context:(id)context subtype:(short)subtype data1:(NSInteger)data1 data2:(NSInteger)data2 {
    NSEvent *event=[self new];event.type=type;event.locationInWindow=point;event.modifierFlags=flags;event.timestamp=time;
    event.windowNumber=number;event.subtype=subtype;event.data1=data1;event.data2=data2;return event;
}
@end

void CPAppKitPostRelativeLook(CGPoint delta,NSTimeInterval timestamp) {
    // A touch displacement is a relative camera input, never a held mouse
    // button or a rate-based thumbstick. Stationary fingers emit no events.
    if(GuestStopped || (!delta.x && !delta.y) || !isfinite(delta.x) || !isfinite(delta.y))return;
    NSWindow *window=NSApp.keyWindow;if(!window)return;
    NSEvent *event=[NSEvent new];event.type=5;event.windowNumber=window.windowNumber;
    event.timestamp=timestamp;event.deltaX=delta.x;event.deltaY=delta.y;event.subtype=0x2077;
    event.locationInWindow=CGPointMake(CGRectGetMidX(window.contentView.bounds),CGRectGetMidY(window.contentView.bounds));
    [NSApp postEvent:event atStart:NO];
}

@implementation NSApplication
+ (instancetype)sharedApplication { static dispatch_once_t once;dispatch_once(&once,^{ NSApp=[self new];NSApp.windows=[NSMutableArray new];NSApp.events=[NSMutableArray new];NSApp.eventCondition=[NSCondition new];});return NSApp; }
- (void)run {
    self.running=YES;Note(@"application_run",@YES);[self finishLaunching];
    // The host calls the guest entry on its own thread. Its AppKit loop may
    // block there while UIKit keeps running on the main thread.
    while(self.running)@autoreleasepool {
        NSEvent *event=[self nextEventMatchingMask:UINT64_MAX untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01] inMode:NSDefaultRunLoopMode dequeue:YES];
        if(event)[self sendEvent:event];
        [self updateWindows];
    }
}
- (void)stop:(id)sender { [self.eventCondition lock];self.running=NO;[self.eventCondition broadcast];[self.eventCondition unlock]; }
- (void)terminate:(id)sender { [self stop:sender];Note(@"termination_requested",@YES); }
- (void)replyToApplicationShouldTerminate:(BOOL)terminate { if(terminate)[self terminate:nil]; }
- (BOOL)isActive { return ApplicationActive; }
- (BOOL)isHidden { return !ApplicationActive; }
- (BOOL)isRunning { return self.running; }
- (void)activateIgnoringOtherApps:(BOOL)ignore { Main(^{[self.keyWindow.nativeWindow makeKeyAndVisible];}); }
- (BOOL)setActivationPolicy:(NSInteger)policy { objc_setAssociatedObject(self,@selector(activationPolicy),@(policy),OBJC_ASSOCIATION_RETAIN_NONATOMIC);return YES; }
- (NSInteger)activationPolicy { return [objc_getAssociatedObject(self,@selector(activationPolicy)) integerValue]; }
- (void)finishLaunching {
    @synchronized(self){if(self.launchFinished)return;self.launchFinished=YES;}
    NSNotification *will=[NSNotification notificationWithName:NSApplicationWillFinishLaunchingNotification object:self];
    [NSNotificationCenter.defaultCenter postNotification:will];Invoke(self.delegate,@"applicationWillFinishLaunching:",will);
    NSNotification *did=[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:self];
    [NSNotificationCenter.defaultCenter postNotification:did];Invoke(self.delegate,@"applicationDidFinishLaunching:",did);
    Note(@"finish_launching",@YES);
}
- (void)hide:(id)sender { for(NSWindow *window in self.windows)[window orderOut:sender]; }
- (void)hideOtherApplications:(id)sender { Note(@"hide_other_applications_unavailable",@YES); }
- (void)unhide:(id)sender { [self.keyWindow orderFront:sender]; }
- (void)setIsVisible:(BOOL)visible { if(visible)[self unhide:nil];else[self hide:nil]; }
- (void)preventWindowOrdering {} // UIKit has no click-driven desktop window ordering.
- (void)addWindowsItem:(NSWindow *)window title:(NSString *)title filename:(BOOL)filename { window.title=title; }
- (NSArray *)orderedWindows { return [self.windows copy]; }
- (NSWindow *)windowWithWindowNumber:(NSInteger)number { for(NSWindow *w in self.windows)if(w.windowNumber==number)return w;return nil; }
- (void)postEvent:(NSEvent *)event atStart:(BOOL)atStart {
    if(!event)return;
    [self.eventCondition lock];NSEvent *tail=self.events.lastObject;
    if(!atStart && event.type==5 && event.subtype==0x2077 && tail.type==5 && tail.subtype==0x2077 && tail.windowNumber==event.windowNumber) {
        // Preserve the full relative displacement; never coalesce across a
        // button/key event or a different window. No additional polling loop.
        tail.deltaX+=event.deltaX;tail.deltaY+=event.deltaY;tail.timestamp=event.timestamp;
    }else if(atStart)[self.events insertObject:event atIndex:0];else[self.events addObject:event];
    [self.eventCondition broadcast];[self.eventCondition unlock];
}
- (NSEvent *)nextEventMatchingMask:(uint64_t)mask untilDate:(NSDate *)date inMode:(NSString *)mode dequeue:(BOOL)dequeue {
    if(!NSThread.isMainThread) {
        // The game's custom AppKit loop has no Core Animation runloop observer.
        // Commit that calling thread's implicit layer transactions explicitly.
        [CATransaction flush];
        static dispatch_once_t once;
        dispatch_once(&once, ^{ Note(@"worker_event_transaction_flush",@YES); });
    }
    NSDate *deadline=date?:NSDate.distantFuture;
    for(;;) {
        [self.eventCondition lock];
        for(NSUInteger i=0;i<self.events.count;i++) {
            NSEvent *event=self.events[i];
            if(event.type<64 && (mask&(1ULL<<event.type))) {
                if(dequeue)[self.events removeObjectAtIndex:i];[self.eventCondition unlock];return event;
            }
        }
        if(deadline.timeIntervalSinceNow<=0){[self.eventCondition unlock];return nil;}
        if(!NSThread.isMainThread) {
            BOOL signaled=[self.eventCondition waitUntilDate:deadline];[self.eventCondition unlock];
            if(!signaled)return nil;
        } else {
            [self.eventCondition unlock];
            [NSRunLoop.mainRunLoop runMode:mode?:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:MIN(.01,deadline.timeIntervalSinceNow)]];
        }
    }
}
- (void)sendEvent:(NSEvent *)event { NSArray *monitors;@synchronized(Monitors){monitors=[Monitors copy];}
    static unsigned observed; if(observed++<12)Note(@"input_dispatch",@{@"type":@(event.type),@"window":@(event.windowNumber),@"point":NSStringFromCGPoint(event.locationInWindow),@"key":@(event.keyCode),@"monitors":@(monitors.count)});
    // Global AppKit monitors observe other applications, never the receiving
    // app's own events. Calling both would cause each guest key press to be deferred
    // twice (for example, one Down skipped two menu rows).
    for(CPMonitor *m in monitors){if(event.type>=64 || !(m.mask&(1ULL<<event.type)))continue;if(m.local){event=m.local(event);if(!event)return;}}
    NSView *view=event.window.contentView;NSDictionary *selectors=@{@1:@"mouseDown:",@2:@"mouseUp:",@3:@"rightMouseDown:",@4:@"rightMouseUp:",@5:@"mouseMoved:",@6:@"mouseDragged:",@7:@"rightMouseDragged:",@8:@"mouseEntered:",@9:@"mouseExited:",@10:@"keyDown:",@11:@"keyUp:",@12:@"flagsChanged:",@22:@"scrollWheel:",@25:@"otherMouseDown:",@26:@"otherMouseUp:",@27:@"otherMouseDragged:"};
    SEL selector=NSSelectorFromString(selectors[@(event.type)]?:@"handleEvent:");if([view respondsToSelector:selector])((void(*)(id,SEL,id))objc_msgSend)(view,selector,event);
}
- (void)updateWindows {
    // The renderer's worker transactions still need to reach Core Animation.
    // Window geometry setters remain synchronous; only redundant layout passes
    // are queued, so a busy UIKit thread no longer stalls every rendered frame.
    [CATransaction flush];
    dispatch_block_t update=^{
        if(GuestStopped)return;
        for(NSWindow *window in [self.windows copy])[window.nativeWindow layoutIfNeeded];
        [CATransaction flush];
    };
    if(NSThread.isMainThread)update();
    else {
        static atomic_bool pending;
        CPRequestCoalescedUpdate(&pending,dispatch_get_main_queue(),update);
    }
}
@end

@implementation NSTrackingArea
- (instancetype)initWithRect:(CGRect)rect options:(NSUInteger)options owner:(id)owner userInfo:(NSDictionary *)info {
    if((self=[super init])){self.rect=rect;self.options=options;self.owner=owner;self.userInfo=info;}return self;
}
@end
@implementation NSWindowController
- (instancetype)initWithWindow:(NSWindow *)window { if((self=[super init]))self.window=window;return self; }
- (void)setWindow:(NSWindow *)window { _window=window; }
- (void)showWindow:(id)sender { [self.window makeKeyAndOrderFront:sender]; }
- (void)close { [self.window close]; }
- (BOOL)isWindowLoaded { return self.window!=nil; }
- (void)loadWindow { NSLog(@"CP_APPKIT nib_loading_unavailable %@",self); }
- (void)windowDidLoad {}
@end
__attribute__((constructor)) static void SetupAppKit(void) {
    Runtime=[NSMutableDictionary new];Monitors=[NSMutableArray new];PausedDisplayLinks=[NSMutableArray new];[NSApplication sharedApplication];
    [NSNotificationCenter.defaultCenter addObserverForName:UIScreenModeDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){
        RefreshScreenGeometry();
        NSNotification *notice=[NSNotification notificationWithName:NSApplicationDidChangeScreenParametersNotification object:NSApp];
        [NSNotificationCenter.defaultCenter postNotification:notice];Invoke(NSApp.delegate,@"applicationDidChangeScreenParameters:",notice);
    }];
}
