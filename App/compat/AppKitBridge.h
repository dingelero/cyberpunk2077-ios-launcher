// Adapted from Stray-iOS (c) 2026 xzk49, MIT license.
// Full notice: AppKitThirdParty.LICENSE. Cyberpunk-specific adaptation.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
FOUNDATION_EXPORT NSDictionary *CPAppKitScreenGeometry(void);
FOUNDATION_EXPORT BOOL CPAppKitPointerCaptured(void);
FOUNDATION_EXPORT void CPAppKitPostRelativeLook(CGPoint delta,NSTimeInterval timestamp);

@class NSApplication, NSWindow, NSEvent, NSScreen;
extern NSApplication *NSApp;
@interface NSView : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic) CGRect bounds;
@property(nonatomic, strong) CALayer *layer;
@property(nonatomic) BOOL wantsLayer;
@property(nonatomic) BOOL wantsExtendedDynamicRangeContent;
@property(nonatomic) NSUInteger autoresizingMask;
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, weak) NSView *superview;
@property(nonatomic, strong) NSMutableArray<NSView *> *subviews;
@property(nonatomic, strong) NSMutableArray *trackingAreas;
@property(nonatomic, strong) UIView *nativeView;
@property(nonatomic) BOOL hidden;
@property(nonatomic) BOOL postsFrameChangedNotifications;
@property(nonatomic) BOOL postsBoundsChangedNotifications;
@property(nonatomic, strong) id nextResponder;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(NSView *)view;
- (void)removeFromSuperview;
- (void)setFrameSize:(CGSize)size;
- (void)setFrameOrigin:(CGPoint)origin;
- (CGRect)convertRect:(CGRect)rect toView:(NSView *)view;
- (CGRect)convertRect:(CGRect)rect fromView:(NSView *)view;
- (CGRect)convertRectToBacking:(CGRect)rect;
- (CGRect)convertRectFromBacking:(CGRect)rect;
- (CALayer *)makeBackingLayer;
- (BOOL)acceptsFirstResponder;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
- (BOOL)isFlipped;
- (void)addTrackingArea:(id)area;
- (void)removeTrackingArea:(id)area;
- (void)updateTrackingAreas;
- (void)registerForDraggedTypes:(NSArray *)types;
- (CGPoint)convertPoint:(CGPoint)point toView:(NSView *)view;
- (CGPoint)convertPoint:(CGPoint)point fromView:(NSView *)view;
@end
@interface NSScreen : NSObject
+ (instancetype)mainScreen;
+ (NSArray *)screens;
- (CGRect)frame;
- (CGRect)visibleFrame;
- (CGFloat)backingScaleFactor;
- (NSDictionary *)deviceDescription;
@end
@interface NSWindow : NSObject
@property(nonatomic) BOOL ignoresMouseEvents;
@property(nonatomic, strong) UIWindow *nativeWindow;
@property(nonatomic, strong) NSView *contentView;
@property(nonatomic, weak) id delegate;
@property(nonatomic) CGRect frame;
@property(nonatomic) NSUInteger styleMask;
@property(nonatomic, readonly) CGRect contentLayoutRect;
@property(nonatomic) NSInteger level;
@property(nonatomic) NSUInteger collectionBehavior;
@property(nonatomic) CGSize minSize;
@property(nonatomic) CGSize maxSize;
@property(nonatomic) CGSize contentAspectRatio;
@property(nonatomic, strong) NSString *title;
@property(nonatomic) NSInteger titleVisibility;
@property(nonatomic) BOOL titlebarAppearsTransparent;
@property(nonatomic) BOOL hasShadow;
@property(nonatomic, getter=isMovable) BOOL movable;
// Preserve the desktop drag preference; UIKit owns the full-screen window.
@property(nonatomic, getter=isMovableByWindowBackground) BOOL movableByWindowBackground;
@property(nonatomic) BOOL opaque;
@property(nonatomic) BOOL releasedWhenClosed;
// The guest disables AppKit's desktop window restoration during creation.
@property(nonatomic, getter=isRestorable) BOOL restorable;
@property(nonatomic) BOOL hidesOnDeactivate;
@property(nonatomic) BOOL acceptsMouseMovedEvents;
@property(nonatomic) CGFloat alphaValue;
@property(nonatomic, strong) id backgroundColor;
@property(nonatomic, strong) id firstResponder;
@property(nonatomic) NSInteger windowNumber;
@property(nonatomic) BOOL visible;
@property(nonatomic) BOOL zoomed;
@property(nonatomic) BOOL miniaturized;
- (instancetype)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)style backing:(NSUInteger)backing defer:(BOOL)defer;
- (CGRect)frameRectForContentRect:(CGRect)rect;
- (void)setFrame:(CGRect)rect display:(BOOL)display;
- (NSScreen *)screen;
- (CGFloat)backingScaleFactor;
- (void)makeKeyAndOrderFront:(id)sender;
- (BOOL)isKeyWindow;
- (void)setIsVisible:(BOOL)visible;
- (void)setFrame:(CGRect)rect display:(BOOL)display animate:(BOOL)animate;
- (void)toggleFullScreen:(id)sender;
- (void)orderFront:(id)sender;
- (void)orderOut:(id)sender;
- (void)close;
- (BOOL)makeFirstResponder:(id)responder;
@end
@interface NSEvent : NSObject
@property(nonatomic) NSUInteger type;
@property(nonatomic) NSUInteger modifierFlags;
@property(nonatomic) NSTimeInterval timestamp;
@property(nonatomic) NSInteger windowNumber;
@property(nonatomic) CGPoint locationInWindow;
@property(nonatomic) CGFloat deltaX;
@property(nonatomic) CGFloat deltaY;
@property(nonatomic) CGFloat scrollingDeltaX;
@property(nonatomic) CGFloat scrollingDeltaY;
@property(nonatomic) NSInteger buttonNumber;
@property(nonatomic) NSInteger clickCount;
@property(nonatomic) uint16_t keyCode;
@property(nonatomic, strong) NSString *characters;
@property(nonatomic, strong) NSString *charactersIgnoringModifiers;
@property(nonatomic) BOOL isARepeat;
@property(nonatomic) short subtype;
@property(nonatomic) NSInteger data1;
@property(nonatomic) NSInteger data2;
- (NSWindow *)window;
+ (id)addLocalMonitorForEventsMatchingMask:(uint64_t)mask handler:(NSEvent *(^)(NSEvent *))handler;
+ (id)addGlobalMonitorForEventsMatchingMask:(uint64_t)mask handler:(void (^)(NSEvent *))handler;
+ (void)removeMonitor:(id)monitor;
@end
@interface NSApplication : NSObject
@property(nonatomic, strong) id delegate;
@property(nonatomic, strong) NSMutableArray<NSWindow *> *windows;
@property(nonatomic, strong) NSMutableArray<NSEvent *> *events;
@property(nonatomic, weak) NSWindow *keyWindow;
@property(nonatomic, weak) NSWindow *mainWindow;
@property(nonatomic, strong) id mainMenu;
@property(nonatomic, strong) id servicesMenu;
@property(nonatomic, strong) id windowsMenu;
@property(nonatomic, strong) id helpMenu;
@property(nonatomic) NSUInteger presentationOptions;
@property(nonatomic, readonly) NSInteger activationPolicy;
- (BOOL)setActivationPolicy:(NSInteger)policy;
@property(nonatomic) BOOL running;
@property(nonatomic, strong) NSCondition *eventCondition;
@property(nonatomic) BOOL launchFinished;
+ (instancetype)sharedApplication;
- (void)run;
- (void)stop:(id)sender;
- (void)replyToApplicationShouldTerminate:(BOOL)terminate;
- (void)postEvent:(NSEvent *)event atStart:(BOOL)atStart;
- (void)sendEvent:(NSEvent *)event;
- (void)finishLaunching;
- (void)updateWindows;
- (NSEvent *)nextEventMatchingMask:(uint64_t)mask untilDate:(NSDate *)date inMode:(NSString *)mode dequeue:(BOOL)dequeue;
- (NSWindow *)windowWithWindowNumber:(NSInteger)number;
@end
void CPAppKitBindHostWindow(UIWindow *window);
UIWindow *CPAppKitHostWindow(void);
void CPAppKitSetApplicationActive(BOOL active);
NSDictionary *CPAppKitRuntimeReport(void);

@interface NSTrackingArea : NSObject
@property(nonatomic) CGRect rect;
@property(nonatomic) NSUInteger options;
@property(nonatomic, weak) id owner;
@property(nonatomic, copy) NSDictionary *userInfo;
- (instancetype)initWithRect:(CGRect)rect options:(NSUInteger)options owner:(id)owner userInfo:(NSDictionary *)info;
@end
@interface NSWindowController : NSObject
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) id owner;
- (instancetype)initWithWindow:(NSWindow *)window;
- (void)showWindow:(id)sender;
- (void)close;
@end
