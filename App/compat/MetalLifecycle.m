#import "MetalLifecycle.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <TargetConditionals.h>
#import <os/lock.h>
#include <stdlib.h>
#import "SimulatorSharedBufferPool.h"
#include "FrameTimeline.h"

static CPMetalLogger CPMetalLog;
static atomic_bool CPMetalActive;
static atomic_ulong CPMetalCommits, CPMetalCompletions, CPMetalPresents, CPMetalPresented, CPMetalErrors, CPMetalBackgroundCommits;
static NSMutableDictionary<NSString *, NSValue *> *CPMetalOriginals;
static NSString *CPLastMetalError;
static NSDictionary *CPMetalCapabilities;
static BOOL CPTraceGPUExecution;
static BOOL CPTraceAllCommands;
static char CPCommandCompletionKey;
typedef struct {double start,end;} CPGPUInterval;
static CPGPUInterval CPGPUIntervals[8192];
static unsigned CPGPUCount,CPGPUCursor;
static os_unfair_lock CPGPULock=OS_UNFAIR_LOCK_INIT;
static void CPRecordGPUExecution(double start,double end) {
    if(start<=0 || end<=start)return;
    os_unfair_lock_lock(&CPGPULock);
    unsigned capacity=CPTraceGPUExecution?8192:256;
    CPGPUIntervals[CPGPUCursor]=(CPGPUInterval){start,end};CPGPUCursor=(CPGPUCursor+1)%capacity;CPGPUCount=MIN(capacity,CPGPUCount+1);
    os_unfair_lock_unlock(&CPGPULock);
}
static int CPCompareGPUInterval(const void *a,const void *b) {
    double x=((const CPGPUInterval *)a)->start,y=((const CPGPUInterval *)b)->start;return (x>y)-(x<y);
}
static NSDictionary *CPGPUExecutionReport(void) {
    CPGPUInterval values[8192];unsigned count;
    os_unfair_lock_lock(&CPGPULock);count=CPGPUCount;memcpy(values,CPGPUIntervals,count*sizeof(CPGPUInterval));os_unfair_lock_unlock(&CPGPULock);
    if(!count)return @{@"enabled":@YES,@"sampleCount":@0};
    qsort(values,count,sizeof(CPGPUInterval),CPCompareGPUInterval);
    double start=values[0].start,end=values[0].end,busy=0,first=start,last=end;
    for(unsigned i=1;i<count;i++) {
        last=MAX(last,values[i].end);
        if(values[i].start>end){busy+=end-start;start=values[i].start;end=values[i].end;}
        else end=MAX(end,values[i].end);
    }
    busy+=end-start;
    return @{@"enabled":@YES,@"sampleCount":@(count),@"windowSeconds":@(last-first),@"executionWindowSeconds":@(busy),
        @"executionWindowPercent":@(last>first?100*busy/(last-first):0),
        @"coverage":CPTraceGPUExecution?@"all command buffers":@"presenting command buffers and first submission",
        @"scope":@"Union of sampled native GPU timestamp intervals; includes waits, excludes unobserved auxiliary commands; not hardware GPU occupancy"};
}
typedef struct {__unsafe_unretained Class cls;SEL selector;IMP original;} CPOriginalEntry;
static CPOriginalEntry CPOriginalCache[128];
static atomic_uint CPOriginalCacheCount;
static void CPCacheOriginal(Class cls,SEL selector,IMP original) {
    @synchronized(CPMetalOriginals) {
        unsigned count=atomic_load(&CPOriginalCacheCount);
        for(unsigned i=0;i<count;i++)if(CPOriginalCache[i].cls==cls && CPOriginalCache[i].selector==selector)return;
        if(count<128){CPOriginalCache[count]=(CPOriginalEntry){cls,selector,original};atomic_store_explicit(&CPOriginalCacheCount,count+1,memory_order_release);}
    }
}
static os_unfair_lock CPFrameLock=OS_UNFAIR_LOCK_INIT;
static CPFrameTimeline CPFrames;
static void CPRecordPresentedTime(double time) {
    if(time<=0)return;
    os_unfair_lock_lock(&CPFrameLock);
    CPFrameAdd(&CPFrames,time);os_unfair_lock_unlock(&CPFrameLock);
}
static int CPCompareInterval(const void *a,const void *b) {double x=*(const double *)a,y=*(const double *)b;return (x>y)-(x<y);}
static NSDictionary *CPFrameReport(void) {
    double values[CP_FRAME_WINDOW],sum=0,last;unsigned count,resets,nonmonotonic,longHitches=0;
    os_unfair_lock_lock(&CPFrameLock);count=CPFrames.count;last=CPFrames.last;resets=CPFrames.resets;nonmonotonic=CPFrames.nonmonotonic;
    memcpy(values,CPFrames.milliseconds,count*sizeof(double));os_unfair_lock_unlock(&CPFrameLock);
    if(!count)return @{ @"sampleCount":@0,@"visibleSceneVerified":@NO };
    for(unsigned i=0;i<count;i++){sum+=values[i];if(values[i]>=500)longHitches++;}qsort(values,count,sizeof(double),CPCompareInterval);
    unsigned worst=MAX(1,(count+99)/100);double worstSum=0;
    for(unsigned i=count-worst;i<count;i++)worstSum+=values[i];
    return @{ @"sampleCount":@(count),@"windowSeconds":@(sum/1000.0),@"averagePresentedFPS":@(1000.0*count/sum),
        @"medianFrameMilliseconds":@(values[count/2]),@"p95FrameMilliseconds":@(values[(count*95-1)/100]),
        @"onePercentLowPresentedFPS":@(1000.0*worst/worstSum),
        @"maximumFrameMilliseconds":@(values[count-1]),@"hitchesAtLeast500Milliseconds":@(longHitches),
        @"secondsSinceLastPresentation":@(MAX(0,CACurrentMediaTime()-last)),
        @"lifecycleResets":@(resets),@"nonmonotonicCallbacksIgnored":@(nonmonotonic),
        @"longForegroundIntervalsIncluded":@YES,
        @"scope":@"All positive native drawable intervals in this foreground window, including loading and long hitches; classify scene and frame generation separately",
        @"visibleSceneVerified":@NO };
}

static NSString *CPMetalMethodKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%s/%s", class_getName(cls), sel_getName(selector)];
}

static IMP CPMetalOriginal(id instance, SEL selector) {
    for (Class cls = object_getClass(instance); cls; cls = class_getSuperclass(cls)) {
        unsigned count=atomic_load_explicit(&CPOriginalCacheCount,memory_order_acquire);
        for(unsigned i=0;i<count;i++)if(CPOriginalCache[i].cls==cls && CPOriginalCache[i].selector==selector)return CPOriginalCache[i].original;
        NSValue *value = CPMetalOriginals[CPMetalMethodKey(cls, selector)];
        if (value) return value.pointerValue;
    }
    return NULL;
}

static void CPMetalRecord(NSString *key, id value) {
    if (CPMetalLog) CPMetalLog(key, value);
    else fprintf(stderr, "CP2077_RUNTIME metal %s=%s\n", key.UTF8String, [value description].UTF8String);
}

// The original macOS renderer asks this macOS-only MTLDevice getter. The iOS
// SDK marks the format unavailable and the getter "Never supported on Apple
// Silicon". Preserve that negative capability instead of inventing a format.
static BOOL CPDepth24Stencil8Unsupported(__unused id device, __unused SEL selector) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CPMetalRecord(@"metalMacOSDepth24Query", @{ @"supported":@NO,
            @"reason":@"Depth24Unorm_Stencil8 is unavailable on iOS and unsupported on Apple Silicon" });
    });
    return NO;
}

static void CPInstallMacOSMetalQueries(id<MTLDevice> device) {
    SEL selector=NSSelectorFromString(@"isDepth24Stencil8PixelFormatSupported");
    if (!device || [device respondsToSelector:selector]) return;
    NSString *encoding=[NSString stringWithFormat:@"%s@:",@encode(BOOL)];
    BOOL added=class_addMethod(object_getClass(device),selector,(IMP)CPDepth24Stencil8Unsupported,encoding.UTF8String);
    CPMetalRecord(@"metalMacOSQueriesInstalled", @{ @"depth24GetterAdded":@(added), @"nativeMethodsReplaced":@NO });
}

#if TARGET_OS_SIMULATOR
static atomic_ulong CPTextureRequests;
typedef id<MTLTexture> (*CPNewTextureIMP)(id, SEL, MTLTextureDescriptor *) __attribute__((ns_returns_retained));
typedef id<MTLTexture> (*CPNewTextureOffsetIMP)(id, SEL, MTLTextureDescriptor *, NSUInteger) __attribute__((ns_returns_retained));
static void CPObserveTextureClass(Class cls);
static void CPRecordTexture(id owner, MTLTextureDescriptor *descriptor) {
    unsigned long sequence=atomic_fetch_add(&CPTextureRequests,1)+1;
    if (sequence<=64 || descriptor.textureType==MTLTextureTypeCubeArray)
        CPMetalRecord(@"simulatorTextureRequest", @{ @"sequence":@(sequence), @"class":@(class_getName(object_getClass(owner))),
            @"textureType":@(descriptor.textureType), @"pixelFormat":@(descriptor.pixelFormat),
            @"width":@(descriptor.width), @"height":@(descriptor.height), @"depth":@(descriptor.depth),
            @"arrayLength":@(descriptor.arrayLength), @"mipmapLevelCount":@(descriptor.mipmapLevelCount),
            @"sampleCount":@(descriptor.sampleCount), @"storageMode":@(descriptor.storageMode),
            @"usage":@(descriptor.usage), @"descriptorModified":@NO });
}
static id<MTLTexture> CPObservedNewTexture(id owner, SEL selector, MTLTextureDescriptor *descriptor) __attribute__((ns_returns_retained));
static id<MTLTexture> CPObservedNewTexture(id owner, SEL selector, MTLTextureDescriptor *descriptor) {
    CPRecordTexture(owner,descriptor);
    CPNewTextureIMP original=(CPNewTextureIMP)CPMetalOriginal(owner,selector);
    return original ? original(owner,selector,descriptor) : nil;
}
static id<MTLTexture> CPObservedNewTextureOffset(id owner, SEL selector, MTLTextureDescriptor *descriptor, NSUInteger offset) __attribute__((ns_returns_retained));
static id<MTLTexture> CPObservedNewTextureOffset(id owner, SEL selector, MTLTextureDescriptor *descriptor, NSUInteger offset) {
    CPRecordTexture(owner,descriptor);
    CPNewTextureOffsetIMP original=(CPNewTextureOffsetIMP)CPMetalOriginal(owner,selector);
    return original ? original(owner,selector,descriptor,offset) : nil;
}
static void CPObserveTextureClass(Class cls) {
    SEL selectors[]={@selector(newTextureWithDescriptor:),@selector(newTextureWithDescriptor:offset:)};
    IMP replacements[]={(IMP)CPObservedNewTexture,(IMP)CPObservedNewTextureOffset};
    for (unsigned i=0;i<2;i++) {
        NSString *key=CPMetalMethodKey(cls,selectors[i]); if(CPMetalOriginals[key])continue;
        Method method=class_getInstanceMethod(cls,selectors[i]);if(!method)continue;
        IMP original=method_getImplementation(method);
        if (original==replacements[i])continue;
        CPMetalOriginals[key]=[NSValue valueWithPointer:original];
        CPCacheOriginal(cls,selectors[i],original);
        class_replaceMethod(cls,selectors[i],replacements[i],method_getTypeEncoding(method));
    }
}
typedef id<MTLHeap> (*CPNewHeapIMP)(id, SEL, MTLHeapDescriptor *) __attribute__((ns_returns_retained));
static id<MTLHeap> CPObservedNewHeap(id<MTLDevice> device, SEL selector, MTLHeapDescriptor *descriptor) __attribute__((ns_returns_retained));
static id<MTLHeap> CPObservedNewHeap(id<MTLDevice> device, SEL selector, MTLHeapDescriptor *descriptor) {
    CPMetalRecord(@"simulatorHeapRequest", @{ @"device": device.name ?: @"", @"size": @(descriptor.size),
        @"storageMode": @(descriptor.storageMode), @"cpuCacheMode": @(descriptor.cpuCacheMode),
        @"hazardTrackingMode": @(descriptor.hazardTrackingMode), @"type": @(descriptor.type),
        @"descriptorModified": @NO });
    // Opt-in failure injection tests whether this game has its own native
    // allocation fallback. Never substitute Private for CPU-accessible Shared.
    const char *probe = getenv("CP_SIM_HEAP_FAILURE_PROBE");
    if (descriptor.storageMode != MTLStorageModePrivate && probe && !strcmp(probe, "1")) {
        CPMetalRecord(@"simulatorHeapFailureProbe", @{ @"returnedNil": @YES, @"storageMode": @(descriptor.storageMode),
            @"scope": @"Simulator-only allocation failure injection; no heap or success fabricated" });
        return nil;
    }
    const char *pool = getenv("CP_SIM_SHARED_BUFFER_POOL");
    if (descriptor.storageMode == MTLStorageModeShared && descriptor.type == MTLHeapTypeAutomatic && pool && !strcmp(pool, "1"))
        return (id<MTLHeap>)[[CPSimulatorSharedBufferPool alloc] initWithDevice:device descriptor:descriptor logger:CPMetalRecord];
    CPNewHeapIMP original = (CPNewHeapIMP)CPMetalOriginal(device, selector);
    id<MTLHeap> heap=original ? original(device, selector, descriptor) : nil;
    if (heap) CPObserveTextureClass(object_getClass(heap));
    return heap;
}
#endif

static void CPAttachCommandCompletion(id<MTLCommandBuffer> command, unsigned long sequence) {
    if(objc_getAssociatedObject(command,&CPCommandCompletionKey))return;
    objc_setAssociatedObject(command,&CPCommandCompletionKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [command addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        CPRecordGPUExecution(buffer.GPUStartTime,buffer.GPUEndTime);
        unsigned long completed = atomic_fetch_add(&CPMetalCompletions, 1) + 1;
        if (buffer.status == MTLCommandBufferStatusError || buffer.error) {
            atomic_fetch_add(&CPMetalErrors, 1);
            NSError *error = buffer.error;
            @synchronized(CPMetalOriginals) { CPLastMetalError = error.localizedDescription ?: @"Metal command buffer reported an error without NSError"; }
            CPMetalRecord(@"metalCommandError", @{ @"status": @(buffer.status), @"domain": error.domain ?: @"", @"code": @(error.code),
                                                  @"description": error.localizedDescription ?: @"", @"commit": @(sequence) });
        } else if (completed == 1 || (CPTraceAllCommands && completed % 300 == 0)) {
            CPMetalRecord(@"metalCommandCompleted", @{ @"completed": @(completed), @"status": @(buffer.status),
                                                      @"gpuStart": @(buffer.GPUStartTime), @"gpuEnd": @(buffer.GPUEndTime) });
        }
    }];
}

static void CPObservedCommit(id<MTLCommandBuffer> command, SEL selector) {
    IMP original = CPMetalOriginal(command, selector);
    if (!original) { CPMetalRecord(@"metalObservationError", @"Original command-buffer commit method unavailable"); return; }
    unsigned long sequence = atomic_fetch_add(&CPMetalCommits, 1) + 1;
    if (!atomic_load(&CPMetalActive)) {
        atomic_fetch_add(&CPMetalBackgroundCommits, 1);
        if(sequence<32 || sequence%300==0)CPMetalRecord(@"metalBackgroundSubmission", @{ @"commit": @(sequence), @"action": @"Forwarded to Metal; renderer lifecycle pause did not stop this submission" });
    }
    // Ordinary auxiliary uploads/decompression buffers get no bridge callback.
    // Presenting buffers retain error observation; explicit diagnostics observe
    // every submission, including GPU timing, just as earlier versions did.
    if(CPTraceAllCommands || sequence==1)CPAttachCommandCompletion(command,sequence);
    ((void (*)(id, SEL))original)(command, selector);
}

static void CPObserveDrawable(id<MTLDrawable> drawable) {
    if (!drawable) return;
    // The native renderer also changes CAMetalLayer properties on a worker
    // without a UIKit runloop. Flush its transactions before native presentation.
    [CATransaction flush];
    unsigned long presents = atomic_fetch_add(&CPMetalPresents, 1) + 1;
#if !TARGET_OS_SIMULATOR
    [drawable addPresentedHandler:^(id<MTLDrawable> actual) {
        CPRecordPresentedTime(actual.presentedTime);
        unsigned long count = atomic_fetch_add(&CPMetalPresented, 1) + 1;
        if (count == 1 || count % 300 == 0) CPMetalRecord(@"metalDrawablePresented", @{ @"count": @(count), @"presentedTime": @(actual.presentedTime) });
    }];
#endif
    if (presents == 1) CPMetalRecord(@"metalPresentScheduled", @{ @"count": @(presents), @"readbackEnabled": @NO });
}

static void CPObservedPresent(id<MTLCommandBuffer> command, SEL selector, id<MTLDrawable> drawable) {
    IMP original = CPMetalOriginal(command, selector); if (!original) return;
    CPAttachCommandCompletion(command,atomic_load(&CPMetalCommits)+1);
    CPObserveDrawable(drawable);
    ((void (*)(id, SEL, id))original)(command, selector, drawable);
}

static void CPObservedPresentTimed(id<MTLCommandBuffer> command, SEL selector, id<MTLDrawable> drawable, double time) {
    IMP original = CPMetalOriginal(command, selector); if (!original) return;
    CPAttachCommandCompletion(command,atomic_load(&CPMetalCommits)+1);
    CPObserveDrawable(drawable);
    ((void (*)(id, SEL, id, double))original)(command, selector, drawable, time);
}

static void CPObserveCommandClass(Class cls) {
    SEL selectors[] = { @selector(commit), @selector(presentDrawable:),
                        NSSelectorFromString(@"presentDrawable:atTime:"), NSSelectorFromString(@"presentDrawable:afterMinimumDuration:") };
    IMP replacements[] = { (IMP)CPObservedCommit, (IMP)CPObservedPresent, (IMP)CPObservedPresentTimed, (IMP)CPObservedPresentTimed };
    for (unsigned i = 0; i < 4; i++) {
        NSString *key = CPMetalMethodKey(cls, selectors[i]);
        if (CPMetalOriginals[key]) continue;
        Method method = class_getInstanceMethod(cls, selectors[i]); if (!method) continue;
        IMP original = method_getImplementation(method);
        // If an inherited class has already been observed, inherit its saved original.
        if (original == replacements[i]) {
            for (Class parent = class_getSuperclass(cls); parent; parent = class_getSuperclass(parent)) {
                NSValue *saved = CPMetalOriginals[CPMetalMethodKey(parent, selectors[i])];
                if (saved) { original = saved.pointerValue; break; }
            }
        }
        CPMetalOriginals[key] = [NSValue valueWithPointer:original];
        CPCacheOriginal(cls,selectors[i],original);
        class_replaceMethod(cls, selectors[i], replacements[i], method_getTypeEncoding(method));
    }
}

void CPInstallMetalLifecycle(CPMetalLogger logger) {
    CPMetalLog = logger;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *trace=getenv("CP2077_TRACE_GPU");CPTraceGPUExecution=trace && !strcmp(trace,"1");
        const char *metalTrace=getenv("CP2077_TRACE_METAL");CPTraceAllCommands=CPTraceGPUExecution || (metalTrace && !strcmp(metalTrace,"1"));
        atomic_store(&CPMetalActive, YES); CPFrameSetActive(&CPFrames,true);CPMetalOriginals = [NSMutableDictionary new];
        id<MTLDevice> device = MTLCreateSystemDefaultDevice(); id<MTLCommandQueue> queue = [device newCommandQueue];
        CPInstallMacOSMetalQueries(device);
        CPMetalCapabilities=@{ @"name":device.name ?: @"unavailable", @"simulator":@(TARGET_OS_SIMULATOR),
            @"supportsApple2":@([device supportsFamily:MTLGPUFamilyApple2]),
            @"supportsApple4":@([device supportsFamily:MTLGPUFamilyApple4]),
            @"supportsApple9":@([device supportsFamily:MTLGPUFamilyApple9]),
            @"supportsBCTextureCompression":@(device.supportsBCTextureCompression),
            @"maxBufferLength":@(device.maxBufferLength), @"queriedNativeDevice":@YES, @"capabilitiesModified":@NO };
        CPMetalRecord(@"metalNativeCapabilities",CPMetalCapabilities);
#if TARGET_OS_SIMULATOR
        CPObserveTextureClass(object_getClass(device));
        Class deviceClass = object_getClass(device); SEL heapSelector = @selector(newHeapWithDescriptor:);
        Method heapMethod = class_getInstanceMethod(deviceClass, heapSelector);
        if (heapMethod) {
            CPMetalOriginals[CPMetalMethodKey(deviceClass, heapSelector)] = [NSValue valueWithPointer:method_getImplementation(heapMethod)];
            class_replaceMethod(deviceClass, heapSelector, (IMP)CPObservedNewHeap, method_getTypeEncoding(heapMethod));
        }
#endif
        if (queue) { CPObserveCommandClass(object_getClass([queue commandBuffer])); CPObserveCommandClass(object_getClass([queue commandBufferWithUnretainedReferences])); }
        CPMetalRecord(@"metalLifecycleInstalled", @{ @"device": device.name ?: @"unavailable", @"observedCommandClasses": CPMetalOriginals.allKeys ?: @[],
                                                    @"changesGPUCapabilities": @NO, @"readbackEnabled": @NO,
                                                    @"presentationCallbacksAvailable": @(!TARGET_OS_SIMULATOR) });
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CPMetalSetApplicationActive(NO); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { CPMetalSetApplicationActive(YES); }];
    });
}

void CPMetalSetApplicationActive(BOOL active) {
    atomic_store(&CPMetalActive, active);
    os_unfair_lock_lock(&CPFrameLock);CPFrameSetActive(&CPFrames,active);os_unfair_lock_unlock(&CPFrameLock);
    CPMetalRecord(@"metalApplicationActive", @(active));
    // The AppKit window/display-link bridge performs the actual pause; do not discard
    // command buffers here, which would strand game waiters and hide real Metal errors.
    [CATransaction flush];
}

BOOL CPMetalApplicationActive(void) { return atomic_load(&CPMetalActive); }

NSDictionary *CPMetalRuntimeReport(void) {
    NSString *last = nil; @synchronized(CPMetalOriginals) { last = CPLastMetalError; }
    return @{ @"active": @(atomic_load(&CPMetalActive)), @"commits": @(atomic_load(&CPMetalCommits)),
              @"completed": @(atomic_load(&CPMetalCompletions)), @"presentScheduled": @(atomic_load(&CPMetalPresents)),
              @"presented": @(atomic_load(&CPMetalPresented)), @"errors": @(atomic_load(&CPMetalErrors)),
              @"backgroundCommits": @(atomic_load(&CPMetalBackgroundCommits)), @"lastError": last ?: NSNull.null,
              @"nativeCapabilities":CPMetalCapabilities ?: @{},
              @"presentationTiming":CPFrameReport(),
              @"gpuExecutionWindows":CPGPUExecutionReport(),
              @"commandCompletionCoverage":CPTraceAllCommands?@"all submissions":@"presenting command buffers and first submission; auxiliary errors require diagnostic launch",
              @"completionSequenceScope":@"Submission sequence at callback registration; approximate for presenting buffers",
              @"presentationCallbacksAvailable": @(!TARGET_OS_SIMULATOR), @"readbackEnabled": @NO, @"gameplayVerified": @NO };
}
