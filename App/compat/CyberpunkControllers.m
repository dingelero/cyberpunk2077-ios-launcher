#import "CyberpunkControllers.h"
#import "TouchControls.h"
#import <GameController/GameController.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#import <mach-o/loader.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdatomic.h>

static CPControllerLogger CPControllerLog;
static BOOL CPControllerTrace, CPGuestMethodsInstalled, CPControllerSlotsReady, CPControllerRegistrationCompleted;
static __weak id CPGameInputDelegate;
static NSMutableDictionary *CPControllerState;
static NSHashTable<GCController *> *CPConfiguredControllers;
static NSMutableDictionary<NSValue *, NSNotification *> *CPPendingNativeControllerEvents;
static NSTimer *CPControllerTimer;
static NSUInteger CPControllerWaitAttempts;
static uintptr_t CPGuestBase;
static IMP CPOriginalSetupNotifications, CPOriginalSetupController, CPOriginalControllerConnect, CPOriginalControllerDisconnect;
static const char *CPSupportedUUID = "A6656ADC-FBE2-36A4-9B9D-B4A9DE645089";
static void CPScheduleControllerSync(void);
static atomic_bool CPControllerGuestStopped;
static BOOL CPControllerSyncInProgress;
static char CPGuardedInputHandlersKey;
static void CPSynchronizePhysicalControllers(void);
static void CPControllerRecord(NSString *key, id value);

// The audited button closures read the live GCController.playerIndex before
// entering the game's four-player array. iOS can deliver queued input after
// disconnection (index -1); desktop code aborts for that index. Forward unchanged
// events only while the real controller has a valid assignment and engine lives.
static BOOL CPControllerCanDeliver(GCController *controller) {
    if (atomic_load(&CPControllerGuestStopped) || !controller) return NO;
    NSCAssert(NSThread.isMainThread,@"Game controller callbacks use the main queue");
    if (![GCController.controllers containsObject:controller] && !CPIsTouchController(controller)) return NO;
    if (controller.playerIndex < 0 || controller.playerIndex > 3) CPSynchronizePhysicalControllers();
    BOOL ready=CPControllerSlotsReady && controller.playerIndex>=0 && controller.playerIndex<4;
    if (!ready) CPScheduleControllerSync();
    return ready;
}
static BOOL CPIsGuestInputBlock(id block) {
    if (!block) return NO;
    struct { void *isa; int flags,reserved; void *invoke; } *layout=(__bridge void *)block;
    Dl_info info={0};
    return dladdr(layout->invoke,&info) && (uintptr_t)info.dli_fbase==CPGuestBase &&
        (uintptr_t)layout->invoke-CPGuestBase>=0x30f28 && (uintptr_t)layout->invoke-CPGuestBase<0x31630;
}
static void CPGuardControllerHandlers(GCController *controller) {
    __weak GCController *weakController=controller;
    NSUInteger guarded=0;
    for (GCControllerButtonInput *button in controller.physicalInputProfile.buttons.allValues) {
        GCControllerButtonValueChangedHandler value=button.valueChangedHandler, pressed=button.pressedChangedHandler;
        NSMutableDictionary *owned=[NSMutableDictionary new];
        if(CPIsGuestInputBlock(value)) {
            GCControllerButtonValueChangedHandler wrapper=^(GCControllerButtonInput *input,float v,BOOL p){if(CPControllerCanDeliver(weakController))value(input,v,p);};
            button.valueChangedHandler=wrapper;owned[@"value"]=wrapper;guarded++;
        }
        if(CPIsGuestInputBlock(pressed)) {
            GCControllerButtonValueChangedHandler wrapper=^(GCControllerButtonInput *input,float v,BOOL p){if(CPControllerCanDeliver(weakController))pressed(input,v,p);};
            button.pressedChangedHandler=wrapper;owned[@"pressed"]=wrapper;guarded++;
        }
        if(owned.count)objc_setAssociatedObject(button,&CPGuardedInputHandlersKey,owned,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for(GCControllerDirectionPad *pad in controller.physicalInputProfile.dpads.allValues) {
        GCControllerDirectionPadValueChangedHandler value=pad.valueChangedHandler;
        if(!CPIsGuestInputBlock(value))continue;
        GCControllerDirectionPadValueChangedHandler wrapper=^(GCControllerDirectionPad *input,float x,float y){if(CPControllerCanDeliver(weakController))value(input,x,y);};
        pad.valueChangedHandler=wrapper;objc_setAssociatedObject(pad,&CPGuardedInputHandlersKey,wrapper,OBJC_ASSOCIATION_RETAIN_NONATOMIC);guarded++;
    }
    CPControllerRecord(@"controllerCallbackLifecycleGuard",@{@"guardedGuestCallbacks":@(guarded),@"playerIndex":@(controller.playerIndex),@"hardwareInputVerified":@NO});
}

static void CPControllerRecord(NSString *key, id value) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ CPControllerRecord(key, value); }); return; }
    if (!CPControllerState) CPControllerState = [NSMutableDictionary new];
    CPControllerState[key] = value ?: NSNull.null;
    if (CPControllerLog) CPControllerLog(key, value);
    else fprintf(stderr, "CP2077_RUNTIME controller %s=%s\n", key.UTF8String, [value description].UTF8String);
}

static BOOL CPReadGuest(uintptr_t address, void *output, size_t size) {
    vm_size_t copied = 0;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)address, (vm_size_t)size, (vm_address_t)output, &copied) == KERN_SUCCESS && copied == size;
}

static uintptr_t CPFindAuditedGuest(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *path = _dyld_get_image_name(i);
        if (!path || ![@(path).lastPathComponent isEqualToString:@"CyberpunkGuest.dylib"]) continue;
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
        if (header->magic != MH_MAGIC_64 || header->sizeofcmds > 1024 * 1024) return 0;
        const uint8_t *cursor = (const void *)(header + 1), *end = cursor + header->sizeofcmds;
        for (uint32_t j = 0; j < header->ncmds; j++) {
            if (cursor + sizeof(struct load_command) > end) return 0;
            const struct load_command *command = (const void *)cursor;
            if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > end) return 0;
            if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
                const struct uuid_command *uuid = (const void *)command;
                NSString *actual = [[[NSUUID alloc] initWithUUIDBytes:uuid->uuid] UUIDString];
                return [actual isEqualToString:@(CPSupportedUUID)] ? (uintptr_t)header : 0;
            }
            cursor += command->cmdsize;
        }
    }
    return 0;
}

static Method CPAuditedMethod(Class cls, const char *name, const char *encoding, uintptr_t expectedOffset) {
    Method method = class_getInstanceMethod(cls, sel_registerName(name));
    if (!method || strcmp(method_getTypeEncoding(method), encoding)) return NULL;
    Dl_info image = {0}; IMP imp = method_getImplementation(method);
    if (!dladdr((const void *)imp, &image) || (uintptr_t)image.dli_fbase != CPGuestBase ||
        (uintptr_t)imp - CPGuestBase != expectedOffset) return NULL;
    return method;
}

static BOOL CPInputSlotsReady(void) {
    if (!CPGuestBase) return NO;
    // Read-only, version-locked readiness guard. Static evidence explains the four pointers.
    // Never write these slots or call desktop methods while they are uninitialized.
    uintptr_t slots[4] = {0};
    if (!CPReadGuest(CPGuestBase + 0x7c63220, slots, sizeof(slots))) return NO;
    for (unsigned i = 0; i < 4; i++) {
        uintptr_t probe = 0;
        if (!slots[i] || !CPReadGuest(slots[i], &probe, sizeof(probe))) return NO;
    }
    return YES;
}

static NSDictionary *CPNativeControllerSnapshot(GCController *controller) {
    GCExtendedGamepad *pad = controller.extendedGamepad;
    NSMutableDictionary *snapshot = [@{ @"vendorName": controller.vendorName ?: @"", @"productCategory": controller.productCategory ?: @"",
                                        @"playerIndex": @(controller.playerIndex), @"extendedGamepad": @(pad != nil),
                                        @"source": CPIsTouchController(controller)?@"Public writable GCController touch profile":@"GCController.controllers", @"hardwareVerified": @NO,
                                        @"softwareSnapshot":@(controller.isSnapshot) } mutableCopy];
    if (pad) {
        snapshot[@"gameCallbacks"] = @{ @"buttonAValue": @(pad.buttonA.valueChangedHandler != nil),
                                         @"buttonAPressed": @(pad.buttonA.pressedChangedHandler != nil),
                                         @"leftStick": @(pad.leftThumbstick.valueChangedHandler != nil),
                                         @"gamepadValue": @(pad.valueChangedHandler != nil) };
        if (CPControllerTrace) snapshot[@"nativeState"] = @{ @"buttonA": @(pad.buttonA.value),
                                                              @"leftX": @(pad.leftThumbstick.xAxis.value),
                                                              @"leftY": @(pad.leftThumbstick.yAxis.value) };
    }
    return snapshot;
}

static void CPSynchronizePhysicalControllers(void) {
    id delegate = CPGameInputDelegate;
    if (atomic_load(&CPControllerGuestStopped) || CPControllerSyncInProgress || !delegate || !CPControllerRegistrationCompleted || !CPInputSlotsReady()) return;
    if (!CPControllerSlotsReady) { CPControllerSlotsReady = YES; CPControllerRecord(@"controllerSlotsReadReady", @YES); }
    NSArray<GCController *> *controllers = CPTouchGameControllers();
    // Register the public software touch profile alongside physical controllers
    // through the game's audited methods. Never fabricate OS notifications.
    Class cls = object_getClass(delegate);
    if (!CPAuditedMethod(cls, "assignControllerToPlayers", "v16@0:8", 0x31630) ||
        !CPAuditedMethod(cls, "setConnectedControllers:", "v24@0:8@16", 0x31df0)) return;
    CPControllerSyncInProgress=YES;
    // Forward only actual notifications previously delivered to this game observer.
    // Do not repost notifications to NotificationCenter or create a controller.
    NSUInteger forwarded = 0, superseded = 0;
    for (NSNotification *event in CPPendingNativeControllerEvents.allValues) {
        GCController *controller = event.object;
        BOOL connectedNow = [controllers containsObject:controller];
        NSArray *registered = ((id (*)(id, SEL))objc_msgSend)(delegate, sel_registerName("connectedControllers"));
        if ([event.name isEqualToString:GCControllerDidConnectNotification]) {
            if (connectedNow && ![registered containsObject:controller]) {
                ((void (*)(id, SEL, id))CPOriginalControllerConnect)(delegate, sel_registerName("controllerDidConnect:"), event);
                forwarded++;
            } else superseded++;
        } else if ([event.name isEqualToString:GCControllerDidDisconnectNotification] && !connectedNow) {
            ((void (*)(id, SEL, id))CPOriginalControllerDisconnect)(delegate, sel_registerName("controllerDidDisconnect:"), event);
            forwarded++;
        } else superseded++;
    }
    [CPPendingNativeControllerEvents removeAllObjects];
    if (forwarded || superseded) CPControllerRecord(@"deferredNativeControllerEvents", @{ @"forwardedToOriginalGameObserver": @(forwarded), @"supersededByCurrentNativeState": @(superseded), @"broadcastNotifications": @0 });
    ((void (*)(id, SEL, id))objc_msgSend)(delegate, sel_registerName("setConnectedControllers:"), [controllers mutableCopy]);
    ((void (*)(id, SEL))objc_msgSend)(delegate, sel_registerName("assignControllerToPlayers"));
    for (GCController *controller in controllers) {
        if (![CPConfiguredControllers containsObject:controller])
            ((void (*)(id, SEL, id))objc_msgSend)(delegate, sel_registerName("setupController:"), controller);
    }
    NSMutableArray *snapshots = [NSMutableArray new];
    for (GCController *controller in controllers) [snapshots addObject:CPNativeControllerSnapshot(controller)];
    CPControllerRecord(@"controllerGameSynchronization", @{ @"realControllerCount": @(controllers.count),
                                                            @"controllers": snapshots, @"gameplayResponseVerified": @NO,
                                                            @"methodInvocationObserved": @YES });
    [CPControllerTimer invalidate]; CPControllerTimer = nil;
    CPControllerSyncInProgress=NO;
}

static void CPControllerTick(__unused NSTimer *timer) {
    if (CPControllerRegistrationCompleted && CPInputSlotsReady() && CPGameInputDelegate) { CPSynchronizePhysicalControllers(); return; }
    if (++CPControllerWaitAttempts >= 120) {
        [CPControllerTimer invalidate]; CPControllerTimer = nil;
        CPControllerRecord(@"controllerSynchronizationPending", @{ @"reason": @"Game registration/input slots were not ready within 30 seconds; unsafe desktop assignment was not called", @"pendingNativeEvents": @(CPPendingNativeControllerEvents.count) });
    }
}

static void CPScheduleControllerSync(void) {
    if (atomic_load(&CPControllerGuestStopped) || CPControllerTimer) return;
    CPControllerWaitAttempts = 0;
    CPControllerTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { CPControllerTick(timer); }];
}
void CPControllersTouchReady(void) {
    dispatch_async(dispatch_get_main_queue(),^{CPScheduleControllerSync();});
}

static void CPSetupNotifications(id self, SEL selector) {
    ((void (*)(id, SEL))CPOriginalSetupNotifications)(self, selector);
    dispatch_async(dispatch_get_main_queue(), ^{
        CPGameInputDelegate = self;
        CPControllerRegistrationCompleted = YES;
        CPControllerRecord(@"controllerNotificationRegistrationObserved", @YES);
        CPScheduleControllerSync();
    });
}

static void CPSetupController(id self, SEL selector, GCController *controller) {
    if (atomic_load(&CPControllerGuestStopped))return;
    ((void (*)(id, SEL, id))CPOriginalSetupController)(self, selector, controller);
    void (^record)(void) = ^{
        CPGuardControllerHandlers(controller);
        if ([CPTouchGameControllers() containsObject:controller]) [CPConfiguredControllers addObject:controller];
        CPControllerRecord(@"controllerGameSetupObserved", CPNativeControllerSnapshot(controller));
    };
    if (NSThread.isMainThread) record(); else dispatch_async(dispatch_get_main_queue(), record);
}

static void CPHandleNativeControllerEvent(id self, SEL selector, NSNotification *event, BOOL connected) {
    if (atomic_load(&CPControllerGuestStopped))return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ CPHandleNativeControllerEvent(self, selector, event, connected); });
        return;
    }
    CPGameInputDelegate = self;
    // These wrappers replace only the UUID/IMP-checked GameApplicationDelegate
    // observers. Other subscribers still receive the untouched native event.
    if (!CPControllerRegistrationCompleted || !CPInputSlotsReady()) {
        if ([event.object isKindOfClass:GCController.class])
            CPPendingNativeControllerEvents[[NSValue valueWithNonretainedObject:event.object]] = event;
        CPControllerRecord(@"nativeControllerEventDeferred", @{ @"notification": event.name ?: @"", @"registered": @(CPControllerRegistrationCompleted),
                                                               @"slotsReady": @NO, @"pendingEvents": @(CPPendingNativeControllerEvents.count),
                                                               @"actualNativeNotification": @YES });
        CPScheduleControllerSync(); return;
    }
    if (connected) {
        NSArray *registered = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("connectedControllers"));
        if ([registered containsObject:event.object]) {
            CPControllerRecord(@"nativeControllerEventAlreadySynchronized", event.name ?: @"");
            return;
        }
    }
    IMP original = connected ? CPOriginalControllerConnect : CPOriginalControllerDisconnect;
    ((void (*)(id, SEL, id))original)(self, selector, event);
    CPControllerRecord(@"nativeControllerEventForwarded", @{ @"notification": event.name ?: @"", @"slotsReady": @YES,
                                                            @"actualNativeNotification": @YES, @"gameplayResponseVerified": @NO });
}

static void CPControllerDidConnect(id self, SEL selector, NSNotification *event) { CPHandleNativeControllerEvent(self, selector, event, YES); }
static void CPControllerDidDisconnect(id self, SEL selector, NSNotification *event) { CPHandleNativeControllerEvent(self, selector, event, NO); }

void CPControllersGuestLoaded(void) {
    if (CPGuestMethodsInstalled) return;
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ CPControllersGuestLoaded(); }); return; }
    CPGuestBase = CPFindAuditedGuest(); Class cls = NSClassFromString(@"GameApplicationDelegate");
    Method notifications = CPAuditedMethod(cls, "setupControllerNotifications", "v16@0:8", 0x31bfc);
    Method setup = CPAuditedMethod(cls, "setupController:", "v24@0:8@16", 0x30ac0);
    Method connect = CPAuditedMethod(cls, "controllerDidConnect:", "v24@0:8@16", 0x31814);
    Method disconnect = CPAuditedMethod(cls, "controllerDidDisconnect:", "v24@0:8@16", 0x3185c);
    Method getter = CPAuditedMethod(cls, "connectedControllers", "@16@0:8", 0x31de8);
    if (!CPGuestBase || !notifications || !setup || !connect || !disconnect || !getter) {
        CPControllerRecord(@"controllerMethodsAccepted", @NO);
        CPControllerRecord(@"controllerMethodError", @"Guest UUID, class, method encoding or implementation offset did not match the audited input.");
        return;
    }
    CPOriginalSetupNotifications = method_setImplementation(notifications, (IMP)CPSetupNotifications);
    CPOriginalSetupController = method_setImplementation(setup, (IMP)CPSetupController);
    CPOriginalControllerConnect = method_setImplementation(connect, (IMP)CPControllerDidConnect);
    CPOriginalControllerDisconnect = method_setImplementation(disconnect, (IMP)CPControllerDidDisconnect);
    CPGuestMethodsInstalled = YES;
    CPControllerRecord(@"controllerMethodsAccepted", @YES);
    CPControllerRecord(@"controllerNativeEventReadinessGuard", @{ @"class": @"GameApplicationDelegate", @"connectOffset": @"0x31814", @"disconnectOffset": @"0x3185c", @"guard": @"registration complete and four native input pointers readable", @"modifiesInputSlots": @NO, @"repostsNativeNotifications": @NO });
    CPControllerRecord(@"controllerMethodVerification", @"Static UUID/method/slot audit accepted. Device callback invocation and gameplay response remain unverified until observed.");
}

void CPInstallControllers(CPControllerLogger logger, BOOL trace) {
    CPControllerLog = logger; CPControllerTrace = trace;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CPControllerState = [NSMutableDictionary new]; CPConfiguredControllers = [NSHashTable weakObjectsHashTable]; CPPendingNativeControllerEvents = [NSMutableDictionary new];
        for (NSNotificationName name in @[GCControllerDidConnectNotification, GCControllerDidDisconnectNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                if ([notification.name isEqualToString:GCControllerDidDisconnectNotification]) [CPConfiguredControllers removeObject:notification.object];
                CPControllerRecord(@"nativeControllerNotification", @{ @"name": notification.name, @"count": @(GCController.controllers.count) });
                if (CPGuestMethodsInstalled && CPGameInputDelegate) CPScheduleControllerSync();
            }];
        CPControllerRecord(@"nativeControllersAtHostStart", @(GCController.controllers.count));
        [GCController startWirelessControllerDiscoveryWithCompletionHandler:^{ CPControllerRecord(@"wirelessDiscoveryCompleted", @YES); }];
        if (trace) {
            [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer *timer) {
                NSMutableArray *snapshots = [NSMutableArray new];
                for (GCController *controller in GCController.controllers) [snapshots addObject:CPNativeControllerSnapshot(controller)];
                CPControllerRecord(@"controllerTrace", snapshots);
            }];
        }
    });
}

NSDictionary *CPControllerRuntimeReport(void) { return [CPControllerState copy] ?: @{}; }

void CPControllersGuestStopped(void) {
    atomic_store(&CPControllerGuestStopped,YES);
    dispatch_async(dispatch_get_main_queue(),^{
        [CPControllerTimer invalidate];CPControllerTimer=nil;
        [NSNotificationCenter.defaultCenter removeObserver:CPGameInputDelegate];
        CPGameInputDelegate=nil;[CPPendingNativeControllerEvents removeAllObjects];
        CPControllerRecord(@"controllerGuestStopped",@YES);
    });
}
