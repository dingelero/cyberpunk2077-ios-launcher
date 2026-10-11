// Custom UIKit controls using a public, writable GameController profile.
#import "TouchControls.h"
#import "TouchLayout.h"
#import "UILanguage.h"
#import "AppKitBridge.h"
#import "CyberpunkControllers.h"
#include "TouchInput.h"
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#include <TargetConditionals.h>
#include <stdlib.h>
#include <float.h>

static NSString *CPBindingTitle(NSDictionary *binding) {return binding[[CPUILanguage() isEqual:@"en"]?@"title_en":@"title"];}
static UIColor *CPCyan(void){return [UIColor colorWithRed:0.20 green:0.91 blue:0.98 alpha:1];}
static UIColor *CPYellow(void){return [UIColor colorWithRed:0.99 green:0.88 blue:0.11 alpha:1];}
static UIBezierPath *CPBevel(CGRect r) {
    CGFloat cut=MIN(9,r.size.height*0.18);UIBezierPath *p=[UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(r.origin.x+cut,r.origin.y)];[p addLineToPoint:CGPointMake(CGRectGetMaxX(r),r.origin.y)];
    [p addLineToPoint:CGPointMake(CGRectGetMaxX(r),CGRectGetMaxY(r)-cut)];
    [p addLineToPoint:CGPointMake(CGRectGetMaxX(r)-cut,CGRectGetMaxY(r))];[p addLineToPoint:CGPointMake(r.origin.x,CGRectGetMaxY(r))];
    [p addLineToPoint:CGPointMake(r.origin.x,r.origin.y+cut)];[p closePath];return p;
}
@interface CPTouchActivity : UIGestureRecognizer
@property(nonatomic,strong) NSMutableSet<UITouch *> *fingers;
@property(nonatomic,copy) void (^activity)(unsigned);
@end
@implementation CPTouchActivity
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if(!self.fingers)self.fingers=[NSMutableSet new];[self.fingers unionSet:touches];if(self.activity)self.activity((unsigned)self.fingers.count);
}
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {if(self.activity)self.activity((unsigned)self.fingers.count);}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.fingers minusSet:touches];if(self.activity)self.activity((unsigned)self.fingers.count);
    if(!self.fingers.count)self.state=UIGestureRecognizerStateFailed;
}
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {[self touchesEnded:touches withEvent:event];}
- (void)reset {[super reset];[self.fingers removeAllObjects];if(self.activity)self.activity(0);}
@end

@interface CPTouchControl : UIView
@property(nonatomic,copy) NSDictionary *definition;
@property(nonatomic,copy) NSString *binding;
@property(nonatomic,strong) UILabel *caption,*code;
@property(nonatomic,strong) UIImageView *icon;
@property(nonatomic,strong) CAShapeLayer *edge;
@property(nonatomic) BOOL pressed,selected,compact;
- (void)refreshStyle;
@end
@implementation CPTouchControl
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.backgroundColor=UIColor.clearColor;
        self.edge=[CAShapeLayer layer];self.edge.lineWidth=1;[self.layer addSublayer:self.edge];
        self.caption=[UILabel new];self.caption.textAlignment=NSTextAlignmentCenter;self.caption.textColor=CPYellow();
        self.caption.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];self.caption.adjustsFontSizeToFitWidth=YES;self.caption.minimumScaleFactor=0.65;
        self.code=[UILabel new];self.code.font=[UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightBold];self.code.textColor=CPCyan();
        self.icon=[UIImageView new];self.icon.contentMode=UIViewContentModeScaleAspectFit;self.icon.tintColor=CPCyan();
        [self addSubview:self.caption];[self addSubview:self.code];[self addSubview:self.icon];self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];self.edge.frame=self.bounds;self.edge.path=CPBevel(CGRectInset(self.bounds,0.7,0.7)).CGPath;
    if(self.compact) {
        self.icon.hidden=YES;self.code.hidden=YES;self.caption.frame=CGRectInset(self.bounds,3,2);self.caption.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    }else {
        self.icon.hidden=NO;self.code.hidden=NO;CGFloat image=MIN(23,self.bounds.size.height*0.41);
        self.icon.frame=CGRectMake((self.bounds.size.width-image)/2,8,image,image);
        self.caption.frame=CGRectMake(3,self.bounds.size.height-19,self.bounds.size.width-6,16);
        self.code.frame=CGRectMake(5,3,self.bounds.size.width-10,10);self.caption.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    }[self refreshStyle];
}
- (void)refreshStyle {
    [CATransaction begin];[CATransaction setDisableActions:YES];
    self.edge.strokeColor=(self.selected?CPYellow():(self.pressed?CPYellow():CPCyan())).CGColor;
    self.edge.fillColor=(self.pressed?[UIColor colorWithRed:0.70 green:0.57 blue:0.03 alpha:0.65]:[UIColor colorWithRed:0.025 green:0.055 blue:0.070 alpha:0.72]).CGColor;
    self.edge.lineWidth=self.selected?2:1;[CATransaction commit];self.icon.tintColor=self.pressed?CPYellow():CPCyan();
}
@end

@interface CPFloatingStick : UIView
@property(nonatomic,strong) UIView *knob;
@end
@implementation CPFloatingStick
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.hidden=YES;self.backgroundColor=[UIColor colorWithRed:0.02 green:0.06 blue:0.08 alpha:0.33];
        self.layer.borderWidth=1;self.layer.borderColor=CPCyan().CGColor;
        self.knob=[UIView new];self.knob.backgroundColor=[CPYellow() colorWithAlphaComponent:0.45];self.knob.layer.borderWidth=1;self.knob.layer.borderColor=CPYellow().CGColor;
        [self addSubview:self.knob];
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];self.layer.cornerRadius=self.bounds.size.width/2;CGFloat size=self.bounds.size.width*0.32;
    self.knob.bounds=CGRectMake(0,0,size,size);self.knob.layer.cornerRadius=size/2;self.knob.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
}
@end

@interface CPTouchOverlay : UIView {
@public
    CPTouchRouter _router;
}
@property(nonatomic,strong) NSMutableArray<CPTouchControl *> *controls;
@property(nonatomic,strong) NSMutableDictionary *layout;
@property(nonatomic,strong) NSDictionary *beforeEditing;
@property(nonatomic,strong) NSCountedSet *heldBindings;
@property(nonatomic,strong) GCController *softwareController;
@property(nonatomic,strong) NSTimer *hideTimer;
@property(nonatomic,strong) CPTouchActivity *activityRecognizer;
@property(nonatomic,strong) CPFloatingStick *floatingStick;
@property(nonatomic,strong) UIView *editorPanel,*keyPane,*lookPane,*bindingList;
@property(nonatomic,strong) UIButton *panelButton;
@property(nonatomic,strong) UILabel *selectionLabel,*editorMessage,*sizeValue,*opacityValue,*sensitivityValue,*aimValue,*radiusValue;
@property(nonatomic,strong) UISlider *sizeSlider,*opacitySlider,*sensitivitySlider,*aimSlider,*radiusSlider;
@property(nonatomic,strong) UISwitch *visibleSwitch,*invertSwitch;
@property(nonatomic,strong) UIButton *bindingButton;
@property(nonatomic) NSInteger selectedIndex,inputMode;
@property(nonatomic) unsigned screenFingers;
@property(nonatomic) double lastActivity,lookX,lookY;
@property(nonatomic) NSUInteger lookEvents;
@property(nonatomic) BOOL physicalPresent,softwareActive,stopped,controlsVisible,editing,pointerCaptured;
@property(nonatomic,copy) NSString *saveError;
- (void)refreshController;
- (void)releaseInputs;
- (void)activity;
- (void)scheduleHide:(double)seconds;
- (void)relayoutControls;
- (void)refreshControls;
@end
static CPTouchOverlay *CPTouchUI;
BOOL CPIsTouchController(GCController *controller){return controller && CPTouchUI.softwareActive && controller==CPTouchUI.softwareController;}
GCController *CPTouchNativeController(void){return CPTouchUI.softwareActive?CPTouchUI.softwareController:nil;}
NSArray<GCController *> *CPTouchGameControllers(void) {
    NSMutableArray *controllers=[GCController.controllers mutableCopy];GCController *touch=CPTouchNativeController();
    if(touch && ![controllers containsObject:touch])[controllers addObject:touch];return controllers;
}
static UILabel *CPLabel(NSString *text,CGFloat size) {
    UILabel *label=[UILabel new];label.text=text;label.textColor=CPCyan();label.font=[UIFont systemFontOfSize:size];return label;
}
static UIButton *CPPanelButton(NSString *title,id target,SEL action) {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:title forState:UIControlStateNormal];[b setTitleColor:CPYellow() forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];[b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];return b;
}
@implementation CPTouchOverlay
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.multipleTouchEnabled=YES;self.backgroundColor=UIColor.clearColor;self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        self.controls=[NSMutableArray new];self.heldBindings=[NSCountedSet new];self.selectedIndex=0;
        NSData *saved=[NSData dataWithContentsOfFile:CPTouchLayoutPath()];
        self.layout=CPTouchValidatedLayout(saved?[NSJSONSerialization JSONObjectWithData:saved options:NSJSONReadingMutableContainers error:nil]:nil);
        // Snapshot profiles are public writable software controllers, not a
        // hardware device or a synthetic OS notification. The original game's
        // audited registration binds the native per-element input callbacks.
        self.softwareController=[GCController controllerWithExtendedGamepad];self.softwareController.handlerQueue=dispatch_get_main_queue();
        for(NSDictionary *definition in CPTouchButtons()) {
            CPTouchControl *control=[CPTouchControl new];control.definition=definition;[self.controls addObject:control];[self addSubview:control];
        }
        self.floatingStick=[CPFloatingStick new];[self addSubview:self.floatingStick];
        self.pointerCaptured=CPAppKitPointerCaptured();
        __weak CPTouchOverlay *weak=self;
        for(NSString *name in @[GCControllerDidConnectNotification,GCControllerDidDisconnectNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){dispatch_async(dispatch_get_main_queue(),^{[weak refreshController];});}];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){
            [weak releaseInputs];weak.screenFingers=0;[weak.activityRecognizer.fingers removeAllObjects];[weak.hideTimer invalidate];weak.hideTimer=nil;
            weak.controlsVisible=NO;[weak refreshControls];
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){dispatch_async(dispatch_get_main_queue(),^{[weak refreshController];});}];
        [self refreshControls];[self activity];
    }return self;
}
- (CGRect)safeArea {return UIEdgeInsetsInsetRect(CGRectInset(self.bounds,8,3),self.safeAreaInsets);}
- (NSMutableDictionary *)setting:(NSInteger)index {return self.layout[@"buttons"][self.controls[index].definition[@"id"]];}
- (BOOL)gameplayGestures {return !self.physicalPresent && !self.editing && (self.inputMode==1 || (self.inputMode==0 && self.pointerCaptured));}
- (void)layoutSubviews {
    [super layoutSubviews];[self relayoutControls];
    CGRect area=[self safeArea];
    if(self.editorPanel && CGRectIsEmpty(self.editorPanel.frame))self.editorPanel.frame=CGRectMake(CGRectGetMidX(area)-174,CGRectGetMidY(area)-136,348,272);
    self.panelButton.frame=CGRectMake(CGRectGetMidX(area)-34,CGRectGetMinY(area)+44,68,30);
}
- (void)relayoutControls {
    CGRect area=[self safeArea];
    for(NSInteger i=0;i<self.controls.count;i++)self.controls[i].frame=CPTouchButtonFrame(self.controls[i].definition,[self setting:i],area);
}
- (void)refreshControls {
    for(NSInteger i=0;i<self.controls.count;i++) {
        CPTouchControl *control=self.controls[i];NSDictionary *setting=[self setting:i];NSString *binding=setting[@"binding"];control.binding=binding;
        NSDictionary *description=CPTouchBinding(binding);NSString *title=CPBindingTitle(description);
        if([CPUILanguage() isEqual:@"en"])title=[[title componentsSeparatedByString:@" / "] firstObject];
        if([CPUILanguage() isEqual:@"en"] && [binding isEqual:@"Y"])title=@"Weapon";
        control.compact=[control.definition[@"anchor"] isEqual:@"CT"];
        if([binding isEqual:@"ui.mode"])title=self.inputMode==0?CPUIString(@"自动",@"Auto"):(self.inputMode==1?CPUIString(@"游玩",@"Play"):CPUIString(@"界面",@"UI"));
        if([binding isEqual:@"ui.edit"])title=self.editing?CPUIString(@"完成",@"Done"):CPUIString(@"布局",@"Layout");
        if([@[@"up",@"down",@"left",@"right"] containsObject:binding])title=description[@"code"];
        control.caption.text=title;control.code.text=description[@"code"];control.icon.image=[UIImage systemImageNamed:description[@"symbol"] ?: @"slider.horizontal.3"];
        BOOL enabled=[setting[@"visible"] boolValue];control.hidden=!enabled && !self.editing;
        control.alpha=(self.controlsVisible || self.editing)?[setting[@"opacity"] doubleValue]*(enabled?1:0.35)*(self.physicalPresent && !self.editing?0.6:1):0;
        control.selected=self.editing && i==self.selectedIndex;[control refreshStyle];
        control.accessibilityLabel=[NSString stringWithFormat:@"%@ · %@",title ?: @"",description[@"code"] ?: binding];
    }
}
- (CPTouchControl *)controlAt:(CGPoint)point {
    if(!self.controlsVisible && !self.editing)return nil;CPTouchControl *nearest=nil;double distance=DBL_MAX;
    // Layout and mode stay reachable even if a custom gameplay key overlaps.
    for(CPTouchControl *control in self.controls) {
        if(control.hidden || !CGRectContainsPoint(CGRectInset(control.frame,-2,-2),point))continue;
        if([control.binding hasPrefix:@"ui."])return control;
        double d=hypot(point.x-control.center.x,point.y-control.center.y);if(d<distance){distance=d;nearest=control;}
    }return nearest;
}
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)event {
    if(self.stopped)return NO;
    if(self.editing || [self gameplayGestures])return CGRectContainsPoint([self safeArea],p);
    if([self controlAt:p])return YES;
    // In menus/map, native canvas clicks and drags pass through.
    return NO;
}
- (void)activity {
    if(self.stopped)return;self.lastActivity=CACurrentMediaTime();
    if(!self.controlsVisible){self.controlsVisible=YES;[self refreshControls];}
    if(!self.hideTimer && !self.editing)[self scheduleHide:4];
}
- (void)scheduleHide:(double)seconds {
    __weak CPTouchOverlay *weak=self;
    self.hideTimer=[NSTimer timerWithTimeInterval:MAX(0.02,seconds) repeats:NO block:^(__unused NSTimer *timer){
        CPTouchOverlay *self=weak;if(!self)return;self.hideTimer=nil;if(self.editing)return;
        if(CPTouchShouldHide(CACurrentMediaTime(),self.lastActivity,self.screenFingers)) {
            self.controlsVisible=NO;[self refreshControls];
        }else if(!self.screenFingers)[self scheduleHide:4-(CACurrentMediaTime()-self.lastActivity)];
    }];[NSRunLoop.mainRunLoop addTimer:self.hideTimer forMode:NSRunLoopCommonModes];
}
- (void)refreshController {
    if(self.stopped || !self.window)return;BOOL physical=NO;
    for(GCController *controller in GCController.controllers)if(controller!=self.softwareController){physical=YES;break;}
#if TARGET_OS_SIMULATOR
    if(getenv("CP_TOUCH_SIMULATOR_PROBE"))physical=NO;
#endif
    BOOL active=!physical;
    if(self.softwareActive!=active || self.physicalPresent!=physical) {
        [self releaseInputs];self.physicalPresent=physical;self.softwareActive=active;CPControllersTouchReady();[self refreshControls];
    }
}
- (GCControllerButtonInput *)nativeButton:(NSString *)binding {
    GCExtendedGamepad *p=self.softwareController.extendedGamepad;
    if([binding isEqual:@"A"])return p.buttonA;if([binding isEqual:@"B"])return p.buttonB;if([binding isEqual:@"X"])return p.buttonX;if([binding isEqual:@"Y"])return p.buttonY;
    if([binding isEqual:@"LT"])return p.leftTrigger;if([binding isEqual:@"RT"])return p.rightTrigger;
    if([binding isEqual:@"LB"])return p.leftShoulder;if([binding isEqual:@"RB"])return p.rightShoulder;
    if([binding isEqual:@"L3"])return p.leftThumbstickButton;if([binding isEqual:@"R3"])return p.rightThumbstickButton;
    if([binding isEqual:@"menu"])return p.buttonMenu;if([binding isEqual:@"options"])return p.buttonOptions;return nil;
}
- (void)emitBinding:(NSString *)binding down:(BOOL)down {
    NSDictionary *description=CPTouchBinding(binding);NSInteger key=[description[@"key"] integerValue];
    if(key>=0) {
        NSEvent *event=[NSEvent new];event.type=down?10:11;event.keyCode=(uint16_t)key;event.windowNumber=NSApp.keyWindow.windowNumber;
        event.timestamp=NSProcessInfo.processInfo.systemUptime;event.characters=@"";event.charactersIgnoringModifiers=@"";[NSApp postEvent:event atStart:NO];return;
    }
    if(!self.softwareActive)return;
    if([@[@"up",@"down",@"left",@"right"] containsObject:binding]) {
        float x=([self.heldBindings countForObject:@"right"]>0)-([self.heldBindings countForObject:@"left"]>0);
        float y=([self.heldBindings countForObject:@"up"]>0)-([self.heldBindings countForObject:@"down"]>0);
        [self.softwareController.extendedGamepad.dpad setValueForXAxis:x yAxis:y];return;
    }
    [[self nativeButton:binding] setValue:down?1:0];
}
- (void)hold:(NSString *)binding down:(BOOL)down {
    NSUInteger before=[self.heldBindings countForObject:binding];if(down)[self.heldBindings addObject:binding];else[self.heldBindings removeObject:binding];
    NSUInteger after=[self.heldBindings countForObject:binding];if((before==0)!=(after==0))[self emitBinding:binding down:after>0];
}
- (void)releaseInputs {
    NSArray *bindings=self.heldBindings.allObjects;[self.heldBindings removeAllObjects];
    for(NSString *binding in bindings)[self emitBinding:binding down:NO];
    [self.softwareController.extendedGamepad.leftThumbstick setValueForXAxis:0 yAxis:0];
    [self.softwareController.extendedGamepad.rightThumbstick setValueForXAxis:0 yAxis:0];
    memset(&_router,0,sizeof(_router));self.floatingStick.hidden=YES;
    for(CPTouchControl *control in self.controls){control.pressed=NO;[control refreshStyle];}
}
- (void)floatingAt:(CGPoint)origin {
    CGFloat radius=[self.layout[@"joystickRadius"] doubleValue];self.floatingStick.frame=CGRectMake(origin.x-radius,origin.y-radius,radius*2,radius*2);
    [self.floatingStick layoutIfNeeded];self.floatingStick.hidden=NO;
}
- (void)moveContact:(CPTouchContact *)contact point:(CGPoint)p timestamp:(double)time {
    if(contact->role==CPTouchMove) {
        CPTouchAxis axis=CPTouchMovement(contact,p.x,p.y,[self.layout[@"joystickRadius"] doubleValue]);
        [self.softwareController.extendedGamepad.leftThumbstick setValueForXAxis:axis.x yAxis:axis.y];
        self.floatingStick.knob.center=CGPointMake(CGRectGetMidX(self.floatingStick.bounds)+axis.x*self.floatingStick.bounds.size.width*0.32,
            CGRectGetMidY(self.floatingStick.bounds)-axis.y*self.floatingStick.bounds.size.height*0.32);
    }else if(contact->role==CPTouchLook) {
        double sensitivity=[self.layout[@"lookSensitivity"] doubleValue];
        if([self.heldBindings countForObject:@"LT"])sensitivity*=[self.layout[@"aimSensitivity"] doubleValue];
        CPTouchDelta delta=CPTouchRelativeLook(contact,p.x,p.y,sensitivity,[self.layout[@"invertLookY"] boolValue]);
        CPAppKitPostRelativeLook(CGPointMake(delta.x,delta.y),time);
        if(delta.x || delta.y){self.lookEvents++;self.lookX+=delta.x;self.lookY+=delta.y;}
    }else if(contact->role==CPTouchEdit) {
        CPTouchControl *control=self.controls[contact->control];CGPoint center=CGPointMake(control.center.x+p.x-contact->lastX,control.center.y+p.y-contact->lastY);
        CGRect area=[self safeArea];NSMutableDictionary *setting=[self setting:contact->control];
        setting[@"x"]=@(MAX(0,MIN(1,(center.x-area.origin.x)/area.size.width)));setting[@"y"]=@(MAX(0,MIN(1,(center.y-area.origin.y)/area.size.height)));
        contact->lastX=p.x;contact->lastY=p.y;[self relayoutControls];
    }
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self refreshController];BOOL wasVisible=self.controlsVisible;[self activity];
    for(UITouch *touch in touches) {
        CGPoint p=[touch locationInView:self];CPTouchControl *control=wasVisible || self.editing?[self controlAt:p]:nil;
        NSInteger index=control?[self.controls indexOfObjectIdenticalTo:control]:-1;
        CPTouchRole role=control?(self.editing && ![control.binding hasPrefix:@"ui."]?CPTouchEdit:CPTouchButton):
            ([self gameplayGestures]?(p.x<CGRectGetMidX([self safeArea])?CPTouchMove:CPTouchLook):CPTouchIgnored);
        CPTouchContact *contact=CPTouchBegin(&_router,(uintptr_t)(__bridge void *)touch,role,(int)index,p.x,p.y);if(!contact)continue;
        if(role==CPTouchButton && control){control.pressed=YES;[control refreshStyle];if(![control.binding hasPrefix:@"ui."])[self hold:control.binding down:YES];}
        else if(contact->role==CPTouchMove)[self floatingAt:p];
        else if(role==CPTouchEdit){self.selectedIndex=index;[self refreshControls];[self refreshEditor];}
    }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for(UITouch *touch in touches) {
        CPTouchContact *contact=CPTouchFind(&_router,(uintptr_t)(__bridge void *)touch);if(!contact)continue;
        // All motion samples use the production router; relative deltas add
        // exactly and don't depend on gesture duration or rendering FPS.
        NSArray *samples=[event coalescedTouchesForTouch:touch];
        // UIKit may provide an empty coalesced list (including Simulator).
        // The delivered touch itself must still move the stick/camera/key.
        if(!samples.count)samples=@[touch];
        for(UITouch *sample in samples)[self moveContact:contact point:[sample locationInView:self] timestamp:sample.timestamp];
    }[self activity];
}
- (void)finishTouches:(NSSet<UITouch *> *)touches cancelled:(BOOL)cancelled {
    for(UITouch *touch in touches) {
        uintptr_t identifier=(uintptr_t)(__bridge void *)touch;CPTouchContact *contact=CPTouchFind(&_router,identifier);if(!contact)continue;
        if(contact->role==CPTouchMove){[self.softwareController.extendedGamepad.leftThumbstick setValueForXAxis:0 yAxis:0];self.floatingStick.hidden=YES;}
        else if(contact->role==CPTouchLook && !cancelled)[self moveContact:contact point:[touch locationInView:self] timestamp:touch.timestamp];
        else if(contact->role==CPTouchButton && contact->control>=0) {
            CPTouchControl *control=self.controls[contact->control];NSString *binding=control.binding;control.pressed=NO;[control refreshStyle];
            BOOL activate=!cancelled && CGRectContainsPoint(CGRectInset(control.frame,-3,-3),[touch locationInView:self]);
            CPTouchEnd(&_router,identifier);
            if([binding isEqual:@"ui.mode"] && activate){[self releaseInputs];self.inputMode=(self.inputMode+1)%3;[self refreshControls];}
            else if([binding isEqual:@"ui.edit"] && activate){if(self.editing)[self finishEditing];else[self beginEditing];}
            else if(![binding hasPrefix:@"ui."])[self hold:binding down:NO];
            continue;
        }CPTouchEnd(&_router,identifier);
    }[self activity];
}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {[self finishTouches:touches cancelled:NO];}
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {[self finishTouches:touches cancelled:YES];}

- (UISlider *)sliderIn:(UIView *)pane y:(CGFloat)y title:(NSString *)title minimum:(float)minimum maximum:(float)maximum action:(SEL)action valueLabel:(UILabel **)valueLabel {
    UILabel *label=CPLabel(title,12);label.frame=CGRectMake(12,y,90,22);[pane addSubview:label];
    UISlider *slider=[UISlider new];slider.minimumValue=minimum;slider.maximumValue=maximum;slider.minimumTrackTintColor=CPCyan();slider.thumbTintColor=CPYellow();
    slider.frame=CGRectMake(101,y-1,168,25);[slider addTarget:self action:action forControlEvents:UIControlEventValueChanged];[pane addSubview:slider];
    UILabel *value=CPLabel(@"",12);value.textColor=CPYellow();value.frame=CGRectMake(277,y,55,22);[pane addSubview:value];*valueLabel=value;return slider;
}
- (void)buildEditor {
    self.editorPanel=[UIView new];self.editorPanel.backgroundColor=[UIColor colorWithRed:0.015 green:0.045 blue:0.060 alpha:0.96];self.editorPanel.layer.borderWidth=1;self.editorPanel.layer.borderColor=CPCyan().CGColor;
    UILabel *header=CPLabel(CPUIString(@"触控配置 · 拖动标题",@"TOUCH · drag title"),13);header.textColor=CPYellow();header.frame=CGRectMake(12,5,160,29);header.userInteractionEnabled=YES;
    [header addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(movePanel:)]];
    [self.editorPanel addSubview:header];
    UIButton *language=CPPanelButton(CPUIString(@"English",@"中文"),self,@selector(toggleLanguage));language.frame=CGRectMake(174,3,96,32);language.accessibilityIdentifier=@"touch-language";[self.editorPanel addSubview:language];
    UIButton *collapse=CPPanelButton(CPUIString(@"收起",@"Hide"),self,@selector(collapsePanel));collapse.frame=CGRectMake(280,3,58,32);[self.editorPanel addSubview:collapse];
    UISegmentedControl *tabs=[[UISegmentedControl alloc] initWithItems:@[CPUIString(@"键位编辑",@"Buttons"),CPUIString(@"镜头 / 摇杆",@"Look / Stick")]];tabs.selectedSegmentIndex=0;tabs.frame=CGRectMake(12,39,324,29);tabs.selectedSegmentTintColor=[CPYellow() colorWithAlphaComponent:0.7];
    [tabs setTitleTextAttributes:@{NSForegroundColorAttributeName:CPCyan()} forState:UIControlStateNormal];
    [tabs setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.blackColor} forState:UIControlStateSelected];
    [tabs addTarget:self action:@selector(editorTab:) forControlEvents:UIControlEventValueChanged];[self.editorPanel addSubview:tabs];
    self.keyPane=[[UIView alloc] initWithFrame:CGRectMake(0,73,348,142)];[self.editorPanel addSubview:self.keyPane];
    self.selectionLabel=CPLabel(CPUIString(@"拖动按钮调整位置；点选调整功能",@"Drag to move; tap to edit"),12);self.selectionLabel.frame=CGRectMake(12,0,324,22);[self.keyPane addSubview:self.selectionLabel];
    self.bindingButton=CPPanelButton(@"",self,@selector(showBindings));self.bindingButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;self.bindingButton.frame=CGRectMake(12,24,324,27);[self.keyPane addSubview:self.bindingButton];
    UILabel *sizeValue=nil,*opacityValue=nil;
    self.sizeSlider=[self sliderIn:self.keyPane y:58 title:CPUIString(@"按钮大小",@"Size") minimum:0.7 maximum:1.65 action:@selector(keySliderChanged:) valueLabel:&sizeValue];self.sizeValue=sizeValue;
    self.opacitySlider=[self sliderIn:self.keyPane y:91 title:CPUIString(@"透明度",@"Opacity") minimum:0.25 maximum:1 action:@selector(keySliderChanged:) valueLabel:&opacityValue];self.opacityValue=opacityValue;
    UILabel *visible=CPLabel(CPUIString(@"显示此按钮",@"Show button"),12);visible.frame=CGRectMake(12,123,160,24);[self.keyPane addSubview:visible];
    self.visibleSwitch=[UISwitch new];self.visibleSwitch.frame=CGRectMake(269,120,50,31);self.visibleSwitch.onTintColor=CPCyan();[self.visibleSwitch addTarget:self action:@selector(keySliderChanged:) forControlEvents:UIControlEventValueChanged];[self.keyPane addSubview:self.visibleSwitch];
    self.lookPane=[[UIView alloc] initWithFrame:self.keyPane.frame];self.lookPane.hidden=YES;[self.editorPanel addSubview:self.lookPane];
    UILabel *sensitivityValue=nil,*aimValue=nil,*radiusValue=nil;
    self.sensitivitySlider=[self sliderIn:self.lookPane y:4 title:CPUIString(@"镜头灵敏度",@"Look speed") minimum:0.2 maximum:5 action:@selector(lookSliderChanged:) valueLabel:&sensitivityValue];self.sensitivityValue=sensitivityValue;
    self.aimSlider=[self sliderIn:self.lookPane y:38 title:CPUIString(@"瞄准倍率",@"Aim multiplier") minimum:0.15 maximum:1.5 action:@selector(lookSliderChanged:) valueLabel:&aimValue];self.aimValue=aimValue;
    self.radiusSlider=[self sliderIn:self.lookPane y:72 title:CPUIString(@"摇杆半径",@"Stick radius") minimum:28 maximum:90 action:@selector(lookSliderChanged:) valueLabel:&radiusValue];self.radiusValue=radiusValue;
    UILabel *invert=CPLabel(CPUIString(@"反转镜头纵向",@"Invert look Y"),12);invert.frame=CGRectMake(12,110,180,24);[self.lookPane addSubview:invert];
    self.invertSwitch=[UISwitch new];self.invertSwitch.frame=CGRectMake(269,107,50,31);self.invertSwitch.onTintColor=CPCyan();[self.invertSwitch addTarget:self action:@selector(lookSliderChanged:) forControlEvents:UIControlEventValueChanged];[self.lookPane addSubview:self.invertSwitch];
    self.editorMessage=CPLabel(CPUIString(@"先暂停游戏再编辑；隐藏键以暗色显示",@"Pause before editing; hidden buttons are dimmed"),10);self.editorMessage.frame=CGRectMake(12,224,324,18);self.editorMessage.adjustsFontSizeToFitWidth=YES;[self.editorPanel addSubview:self.editorMessage];
    NSArray *titles=@[CPUIString(@"取消",@"Cancel"),CPUIString(@"全部默认",@"Reset all"),CPUIString(@"保存完成",@"Save / Done")];SEL actions[]={@selector(cancelEditing),@selector(resetLayout),@selector(finishEditing)};
    for(unsigned i=0;i<3;i++){UIButton *b=CPPanelButton(titles[i],self,actions[i]);b.frame=CGRectMake(8+i*112,241,108,28);[self.editorPanel addSubview:b];}
    [self addSubview:self.editorPanel];self.panelButton=CPPanelButton(CPUIString(@"参数",@"Settings"),self,@selector(expandPanel));[self addSubview:self.panelButton];
}
- (void)beginEditing {
    [self releaseInputs];self.beforeEditing=CPTouchValidatedLayout(self.layout);self.editing=YES;self.controlsVisible=YES;[self.hideTimer invalidate];self.hideTimer=nil;
    if(!self.editorPanel)[self buildEditor];self.editorPanel.hidden=NO;self.panelButton.hidden=NO;self.saveError=nil;[self refreshControls];[self refreshEditor];[self setNeedsLayout];
}
- (void)endEditor {
    self.editing=NO;self.editorPanel.hidden=YES;self.panelButton.hidden=YES;[self.bindingList removeFromSuperview];self.bindingList=nil;
    self.beforeEditing=nil;[self releaseInputs];[self relayoutControls];[self refreshControls];[self activity];
}
- (void)finishEditing {
    self.layout=CPTouchValidatedLayout(self.layout);NSString *path=CPTouchLayoutPath();NSError *error=nil;
    BOOL directory=[NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error];
    NSData *data=[NSJSONSerialization dataWithJSONObject:self.layout options:NSJSONWritingPrettyPrinted error:&error];
    if(!directory || !data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        self.saveError=error.localizedDescription ?: CPUIString(@"无法保存键位",@"Cannot save layout");self.editorMessage.text=self.saveError;self.editorMessage.textColor=UIColor.systemRedColor;return;
    }self.saveError=nil;[self endEditor];
}
- (void)toggleLanguage {
    [self releaseInputs];CPSetUILanguage([CPUILanguage() isEqual:@"en"]?@"zh":@"en");
    CGRect frame=self.editorPanel.frame;BOOL lookTab=!self.lookPane.hidden;
    [self.bindingList removeFromSuperview];self.bindingList=nil;[self.editorPanel removeFromSuperview];[self.panelButton removeFromSuperview];
    [self buildEditor];self.editorPanel.frame=frame;self.keyPane.hidden=lookTab;self.lookPane.hidden=!lookTab;
    for(UIView *view in self.editorPanel.subviews)if([view isKindOfClass:UISegmentedControl.class])[(UISegmentedControl *)view setSelectedSegmentIndex:lookTab?1:0];
    [self refreshControls];[self refreshEditor];[self setNeedsLayout];
}
- (void)cancelEditing {self.layout=CPTouchValidatedLayout(self.beforeEditing);self.saveError=nil;[self endEditor];}
- (void)resetLayout {self.layout=CPTouchDefaultLayout();[self relayoutControls];[self refreshControls];[self refreshEditor];}
- (void)collapsePanel {self.editorPanel.hidden=YES;[self.bindingList removeFromSuperview];self.bindingList=nil;}
- (void)expandPanel {self.editorPanel.hidden=NO;}
- (void)movePanel:(UIPanGestureRecognizer *)gesture {
    CGPoint delta=[gesture translationInView:self];CGRect area=[self safeArea];CGRect frame=self.editorPanel.frame;frame.origin.x+=delta.x;frame.origin.y+=delta.y;
    frame.origin.x=MAX(area.origin.x,MIN(CGRectGetMaxX(area)-frame.size.width,frame.origin.x));frame.origin.y=MAX(area.origin.y,MIN(CGRectGetMaxY(area)-frame.size.height,frame.origin.y));
    self.editorPanel.frame=frame;[gesture setTranslation:CGPointZero inView:self];
}
- (void)editorTab:(UISegmentedControl *)sender {self.keyPane.hidden=sender.selectedSegmentIndex!=0;self.lookPane.hidden=sender.selectedSegmentIndex!=1;[self.bindingList removeFromSuperview];self.bindingList=nil;}
- (void)refreshEditor {
    if(!self.editing)return;NSDictionary *setting=[self setting:self.selectedIndex];NSString *binding=setting[@"binding"];
    self.selectionLabel.text=[NSString stringWithFormat:CPUIString(@"选中：%@ · 拖动调整位置",@"Selected: %@ · drag to move"),self.controls[self.selectedIndex].caption.text ?: @""];
    [self.bindingButton setTitle:[NSString stringWithFormat:CPUIString(@"功能绑定：%@  ›",@"Binding: %@  ›"),CPBindingTitle(CPTouchBinding(binding)) ?: CPUIString(@"系统入口（固定）",@"System control (fixed)")] forState:UIControlStateNormal];
    self.bindingButton.enabled=![binding hasPrefix:@"ui."];self.visibleSwitch.enabled=![binding hasPrefix:@"ui."];
    self.sizeSlider.value=[setting[@"scale"] floatValue];self.opacitySlider.value=[setting[@"opacity"] floatValue];self.visibleSwitch.on=[setting[@"visible"] boolValue];
    self.sizeValue.text=[NSString stringWithFormat:@"%.2f×",self.sizeSlider.value];self.opacityValue.text=[NSString stringWithFormat:@"%.0f%%",self.opacitySlider.value*100];
    self.sensitivitySlider.value=[self.layout[@"lookSensitivity"] floatValue];self.aimSlider.value=[self.layout[@"aimSensitivity"] floatValue];self.radiusSlider.value=[self.layout[@"joystickRadius"] floatValue];self.invertSwitch.on=[self.layout[@"invertLookY"] boolValue];
    self.sensitivityValue.text=[NSString stringWithFormat:@"%.2f",self.sensitivitySlider.value];self.aimValue.text=[NSString stringWithFormat:@"%.2f×",self.aimSlider.value];self.radiusValue.text=[NSString stringWithFormat:@"%.0f",self.radiusSlider.value];
    self.editorMessage.text=self.saveError ?: CPUIString(@"拖动键位；收起面板可编辑被遮住的按钮",@"Drag buttons; hide this panel to reach covered buttons");self.editorMessage.textColor=self.saveError?UIColor.systemRedColor:CPCyan();
}
- (void)keySliderChanged:(id)sender {
    NSMutableDictionary *setting=[self setting:self.selectedIndex];setting[@"scale"]=@(self.sizeSlider.value);setting[@"opacity"]=@(self.opacitySlider.value);
    if(self.visibleSwitch.enabled)setting[@"visible"]=@(self.visibleSwitch.on);
    [self relayoutControls];[self refreshControls];[self refreshEditor];
}
- (void)lookSliderChanged:(id)sender {
    self.layout[@"lookSensitivity"]=@(self.sensitivitySlider.value);self.layout[@"aimSensitivity"]=@(self.aimSlider.value);
    self.layout[@"joystickRadius"]=@(self.radiusSlider.value);self.layout[@"invertLookY"]=@(self.invertSwitch.on);[self refreshEditor];
}
- (void)showBindings {
    [self.bindingList removeFromSuperview];UIScrollView *list=[[UIScrollView alloc] initWithFrame:CGRectMake(8,72,332,163)];
    list.backgroundColor=[UIColor colorWithRed:0.015 green:0.045 blue:0.06 alpha:1];list.layer.borderWidth=1;list.layer.borderColor=CPCyan().CGColor;
    NSArray *bindings=CPTouchBindings();for(NSUInteger i=0;i<bindings.count;i++) {
        UIButton *button=CPPanelButton([NSString stringWithFormat:@"%@ · %@",bindings[i][@"code"],CPBindingTitle(bindings[i])],self,@selector(chooseBinding:));
        button.tag=(NSInteger)i;button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;button.frame=CGRectMake(9,i*36,312,36);[list addSubview:button];
    }list.contentSize=CGSizeMake(332,bindings.count*36);self.bindingList=list;[self.editorPanel addSubview:list];
}
- (void)chooseBinding:(UIButton *)button {
    [self setting:self.selectedIndex][@"binding"]=CPTouchBindings()[button.tag][@"id"];[self.bindingList removeFromSuperview];self.bindingList=nil;[self refreshControls];[self refreshEditor];
}
@end

void CPAttachTouchControls(UIWindow *window) {
    NSCAssert(NSThread.isMainThread,@"Touch UI uses UIKit's main thread");if(!window)return;
    if(!CPTouchUI)CPTouchUI=[[CPTouchOverlay alloc] initWithFrame:window.bounds];
    if(CPTouchUI.activityRecognizer.view!=window) {
        [CPTouchUI.activityRecognizer.view removeGestureRecognizer:CPTouchUI.activityRecognizer];
        CPTouchActivity *monitor=[[CPTouchActivity alloc] initWithTarget:nil action:nil];monitor.cancelsTouchesInView=NO;monitor.delaysTouchesBegan=NO;monitor.delaysTouchesEnded=NO;
        monitor.activity=^(unsigned fingers){CPTouchUI.screenFingers=fingers;[CPTouchUI activity];};CPTouchUI.activityRecognizer=monitor;[window addGestureRecognizer:monitor];
    }CPTouchUI.frame=window.bounds;[window addSubview:CPTouchUI];[window bringSubviewToFront:CPTouchUI];[CPTouchUI setNeedsLayout];[CPTouchUI refreshController];
}
void CPTouchControlsPointerCaptureChanged(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        if(!CPTouchUI)return;BOOL captured=CPAppKitPointerCaptured();
        if(CPTouchUI.pointerCaptured!=captured){if(CPTouchUI.inputMode==0)[CPTouchUI releaseInputs];CPTouchUI.pointerCaptured=captured;[CPTouchUI refreshControls];}
    });
}
NSDictionary *CPTouchControlsReport(void) {
    NSCAssert(NSThread.isMainThread,@"Touch state report uses UIKit's main thread");
    if(!CPTouchUI)return @{@"installed":@NO,@"version":@"touch-v4-language",@"gameplayResponseVerified":@NO};
    NSMutableArray *buttons=[NSMutableArray new];
    for(CPTouchControl *control in CPTouchUI.controls)[buttons addObject:@{@"id":control.definition[@"id"],@"binding":control.binding ?: @"",@"frame":NSStringFromCGRect(control.frame),@"hidden":@(control.hidden),@"pressed":@(control.pressed)}];
    unsigned contacts=0;for(unsigned i=0;i<10;i++)if(CPTouchUI->_router.contacts[i].identifier)contacts++;
    GCExtendedGamepad *p=CPTouchUI.softwareController.extendedGamepad;
    return @{@"installed":@(CPTouchUI!=nil),@"version":@"touch-v4-language",@"uiLanguage":CPUILanguage(),@"visible":@(CPTouchUI.controlsVisible),@"autoHideSeconds":@4,
        @"buttons":buttons,@"activeTouches":@(contacts),@"floatingLeftStickVisible":@(!CPTouchUI.floatingStick.hidden),@"floatingLeftStickCenter":NSStringFromCGPoint(CPTouchUI.floatingStick.center),
        @"fixedLeftOrRightStickVisible":@NO,@"rightLookRelativeEvents":@(CPTouchUI.lookEvents),@"rightLookAccumulatedX":@(CPTouchUI.lookX),@"rightLookAccumulatedY":@(CPTouchUI.lookY),
        @"inputMode":@(CPTouchUI.inputMode),@"nativePointerCaptured":@(CPTouchUI.pointerCaptured),@"gameplayTouchRegionsEnabled":@([CPTouchUI gameplayGestures]),
        @"editing":@(CPTouchUI.editing),@"settingsPath":CPTouchLayoutPath(),@"saveError":CPTouchUI.saveError ?: NSNull.null,@"settings":CPTouchUI.layout ?: @{},
        @"nativeVirtualControllerConnected":@(CPTouchUI.softwareActive),@"controllerAPI":@"Public writable GCController extended-gamepad snapshot; original per-element callbacks",
        @"controllerIsSnapshot":@(CPTouchUI.softwareController.isSnapshot),@"completeNativeButtons":@(p.leftThumbstickButton && p.rightThumbstickButton && p.buttonOptions && p.buttonMenu && p.dpad),
        @"physicalControllerHasPriority":@YES,@"physicalControllerPresent":@(CPTouchUI.physicalPresent),@"gameplayResponseVerified":@NO,
        @"drawing":@"Static UIKit shapes; input is touch-event driven, no camera polling or per-frame UI timer"};
}
void CPTouchControlsGuestStopped(void) {
    dispatch_async(dispatch_get_main_queue(),^{[CPTouchUI releaseInputs];CPTouchUI.stopped=YES;CPTouchUI.softwareActive=NO;[CPTouchUI.hideTimer invalidate];[CPTouchUI removeFromSuperview];});
}
