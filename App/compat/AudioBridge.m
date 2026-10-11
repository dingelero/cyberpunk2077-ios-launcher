#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <stdatomic.h>
#include <math.h>

// The desktop HAL ABI uses three UInt32 fields even where its header is not
// present in the iOS SDK. Our route object represents the real session output;
// it is not an invented hardware device or a promise that arbitrary HAL APIs
// will succeed.
typedef struct { UInt32 selector, scope, element; } CPAudioAddress;
enum { CPOutputObject = 0x43500001, CPSystemObject = 1 };
enum { CPParamError = -50, CPUnknownProperty = 'who?', CPBadSize = '!siz', CPBadObject = '!obj', CPIllegalOperation = 'nope', CPUnsupported = 'unop' };
static atomic_ullong CPCallbacks, CPNonzeroCallbacks;
static atomic_uint CPRenderErrors;
static BOOL CPAudioSessionActive;
static NSError *CPAudioSessionError;
static NSMutableDictionary<NSValue *, id> *CPGraphs;
static dispatch_source_t CPMeter;

@interface CPAudioCallback : NSObject { @public AURenderCallbackStruct original; }
@end
@implementation CPAudioCallback @end
@interface CPAudioGraph : NSObject
@property(nonatomic) AUGraph graph;
@property(nonatomic) BOOL wantedRunning;
@property(nonatomic) BOOL paused;
@property(nonatomic, strong) NSMutableArray<CPAudioCallback *> *renderContexts;
@end
@implementation CPAudioGraph @end

static void *CPAudioSymbol(const char *framework, const char *name) {
    // An explicit image handle cannot resolve a libCPCompat alias back to us.
    void *image = dlopen(framework, RTLD_NOW | RTLD_LOCAL);
    return image ? dlsym(image, name) : NULL;
}
static BOOL CPAudioActivate(void) {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;
    BOOL result = [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error];
    if (result) result = [session setPreferredSampleRate:48000 error:&error];
    if (result) result = [session setActive:YES error:&error];
    CPAudioSessionActive = result;
    CPAudioSessionError = error;
    fprintf(stderr, "CP_AUDIO session active=%d rate=%.0f duration=%.6f channels=%lu route=%s error=%s\n", result, session.sampleRate, session.IOBufferDuration, (unsigned long)session.outputNumberOfChannels, session.currentRoute.description.UTF8String, error.description.UTF8String ?: "none");
    return result;
}
static BOOL CPHasOutput(void) {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    return session.currentRoute.outputs.count > 0 && session.outputNumberOfChannels > 0 && session.sampleRate > 0;
}
static UInt32 CPPropertySize(UInt32 object, const CPAudioAddress *address) {
    if (!address || address->element != 0 || !CPHasOutput()) return 0;
    if (object == CPSystemObject && address->scope == 'glob') {
        if (address->selector == 'dOut' || address->selector == 'sOut' || address->selector == 'dev#') return sizeof(UInt32);
    }
    if (object != CPOutputObject || (address->scope != 'glob' && address->scope != 'outp')) return 0;
    switch (address->selector) {
        case 'fsiz': case 'ltnc': case 'livn': return sizeof(UInt32);
        case 'nsrt': return sizeof(Float64);
        case 'lnam': case 'uid ': return sizeof(CFStringRef);
        case 'slay': return offsetof(AudioBufferList, mBuffers) + sizeof(AudioBuffer);
        default: return 0;
    }
}
OSStatus CPAudioObjectGetPropertyDataSize(UInt32 object, const CPAudioAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 *size) {
    if (!address || !size) return CPParamError;
    UInt32 required = qualifierSize == 0 ? CPPropertySize(object, address) : 0;
    if (required) { *size = required; return noErr; }
    typedef OSStatus (*Fn)(UInt32, const CPAudioAddress *, UInt32, const void *, UInt32 *);
    static Fn native; static dispatch_once_t once;
    dispatch_once(&once, ^{ native = CPAudioSymbol("/System/Library/Frameworks/CoreAudio.framework/CoreAudio", "AudioObjectGetPropertyDataSize"); });
    OSStatus status = native ? native(object, address, qualifierSize, qualifier, size) : CPUnknownProperty;
    fprintf(stderr, "CP_AUDIO hal_size object=%u selector=%08x status=%d size=%u\n", object, address->selector, (int)status, status == noErr ? *size : 0);
    return status;
}
OSStatus CPAudioObjectGetPropertyData(UInt32 object, const CPAudioAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 *size, void *data) {
    if (!address || !size || !data) return CPParamError;
    UInt32 required = qualifierSize == 0 ? CPPropertySize(object, address) : 0;
    if (required) {
        if (*size < required) { *size = required; return CPBadSize; }
        AVAudioSession *session = AVAudioSession.sharedInstance;
        switch (address->selector) {
            case 'dOut': case 'sOut': case 'dev#': *(UInt32 *)data = CPOutputObject; break;
            case 'fsiz': *(UInt32 *)data = (UInt32)llround(session.IOBufferDuration * session.sampleRate); break;
            case 'nsrt': *(Float64 *)data = session.sampleRate; break;
            case 'ltnc': *(UInt32 *)data = (UInt32)llround(session.outputLatency * session.sampleRate); break;
            case 'livn': *(UInt32 *)data = CPHasOutput() ? 1 : 0; break;
            case 'lnam': *(CFStringRef *)data = CFBridgingRetain(session.currentRoute.outputs.firstObject.portName); break;
            case 'uid ': *(CFStringRef *)data = CFBridgingRetain(session.currentRoute.outputs.firstObject.UID); break;
            case 'slay': {
                AudioBufferList *list = data; list->mNumberBuffers = 1;
                list->mBuffers[0] = (AudioBuffer){ (UInt32)session.outputNumberOfChannels, 0, NULL }; break;
            }
            default: return CPUnknownProperty;
        }
        *size = required;
        fprintf(stderr, "CP_AUDIO hal_get object=%u selector=%08x size=%u status=0 (session route)\n", object, address->selector, required);
        return noErr;
    }
    typedef OSStatus (*Fn)(UInt32, const CPAudioAddress *, UInt32, const void *, UInt32 *, void *);
    static Fn native; static dispatch_once_t once;
    dispatch_once(&once, ^{ native = CPAudioSymbol("/System/Library/Frameworks/CoreAudio.framework/CoreAudio", "AudioObjectGetPropertyData"); });
    OSStatus status = native ? native(object, address, qualifierSize, qualifier, size, data) : CPUnknownProperty;
    fprintf(stderr, "CP_AUDIO hal_get object=%u selector=%08x status=%d\n", object, address->selector, (int)status);
    return status;
}
OSStatus CPAudioObjectSetPropertyData(UInt32 object, const CPAudioAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 size, const void *data) {
    if (!address || !data) return CPParamError;
    if (object == CPOutputObject && qualifierSize == 0 && address->element == 0 && (address->scope == 'glob' || address->scope == 'outp')) {
        AVAudioSession *session = AVAudioSession.sharedInstance; NSError *error = nil; BOOL accepted = NO;
        if (address->selector == 'fsiz') {
            if (size != sizeof(UInt32)) return CPBadSize;
            UInt32 frames = *(const UInt32 *)data;
            if (!frames || frames > 65536 || session.sampleRate <= 0) return CPParamError;
            accepted = [session setPreferredIOBufferDuration:frames / session.sampleRate error:&error];
        } else if (address->selector == 'nsrt') {
            if (size != sizeof(Float64)) return CPBadSize;
            Float64 rate = *(const Float64 *)data;
            if (!isfinite(rate) || rate <= 0) return CPParamError;
            accepted = [session setPreferredSampleRate:rate error:&error];
        } else return CPUnsupported;
        fprintf(stderr, "CP_AUDIO session_preference selector=%08x accepted=%d actual_rate=%.0f actual_duration=%.6f error=%s\n", address->selector, accepted, session.sampleRate, session.IOBufferDuration, error.description.UTF8String ?: "none");
        return accepted ? noErr : CPIllegalOperation;
    }
    typedef OSStatus (*Fn)(UInt32, const CPAudioAddress *, UInt32, const void *, UInt32, const void *);
    static Fn native; static dispatch_once_t once;
    dispatch_once(&once, ^{ native = CPAudioSymbol("/System/Library/Frameworks/CoreAudio.framework/CoreAudio", "AudioObjectSetPropertyData"); });
    OSStatus status = native ? native(object, address, qualifierSize, qualifier, size, data) : CPUnsupported;
    fprintf(stderr, "CP_AUDIO hal_set object=%u selector=%08x status=%d\n", object, address->selector, (int)status);
    return status;
}

#define CP_AUDIO_NATIVE(Name, Type) static Type native; static dispatch_once_t once; dispatch_once(&once, ^{ native = CPAudioSymbol("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", Name); }); if (!native) return kAudio_UnimplementedError;
OSStatus CPAUGraphAddNode(AUGraph graph, const AudioComponentDescription *description, AUNode *node) {
    if (!description || !node) return CPParamError;
    typedef OSStatus (*Fn)(AUGraph, const AudioComponentDescription *, AUNode *); CP_AUDIO_NATIVE("AUGraphAddNode", Fn)
    AudioComponentDescription adapted = *description;
    BOOL desktopOutput = adapted.componentType == kAudioUnitType_Output && (adapted.componentSubType == 'def ' || adapted.componentSubType == 'ahal');
    if (desktopOutput) {
        if (!CPAudioActivate()) return CPIllegalOperation;
        adapted.componentSubType = kAudioUnitSubType_RemoteIO;
    }
    OSStatus status = native(graph, &adapted, node);
    if (status == noErr && adapted.componentType == kAudioUnitType_Output) {
        @synchronized(CPGraphs) { CPAudioGraph *value = CPGraphs[[NSValue valueWithPointer:graph]]; if (!value) { value = [CPAudioGraph new]; value.graph = graph; value.renderContexts = [NSMutableArray new]; CPGraphs[[NSValue valueWithPointer:graph]] = value; } }
    }
    fprintf(stderr, "CP_AUDIO graph_node type=%08x source_subtype=%08x native_subtype=%08x status=%d\n", description->componentType, description->componentSubType, adapted.componentSubType, (int)status);
    return status;
}
static void CPCountPCM(OSStatus status, AudioBufferList *buffers) {
    atomic_fetch_add_explicit(&CPCallbacks, 1, memory_order_relaxed);
    if (status) { atomic_fetch_add_explicit(&CPRenderErrors, 1, memory_order_relaxed); return; }
    // Count nonzero bytes without assuming a Float32/Int16 stream format.
    // The realtime path uses only reads and atomic counters.
    BOOL nonzero = NO;
    if (buffers) for (UInt32 b = 0; b < buffers->mNumberBuffers && !nonzero; b++) {
        const unsigned char *bytes = buffers->mBuffers[b].mData;
        if (bytes) for (UInt32 i = 0; i < buffers->mBuffers[b].mDataByteSize; i++) if (bytes[i]) { nonzero = YES; break; }
    }
    if (nonzero) atomic_fetch_add_explicit(&CPNonzeroCallbacks, 1, memory_order_relaxed);
}
static OSStatus CPRenderAudio(void *context, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *buffers) {
    __unsafe_unretained CPAudioCallback *contextValue = (__bridge CPAudioCallback *)context;
    AURenderCallbackStruct callback = contextValue->original;
    OSStatus status = callback.inputProc(callback.inputProcRefCon, flags, time, bus, frames, buffers);
    CPCountPCM(status, buffers); return status;
}
OSStatus CPAUGraphSetNodeInputCallback(AUGraph graph, AUNode node, UInt32 input, const AURenderCallbackStruct *callback) {
    typedef OSStatus (*Fn)(AUGraph, AUNode, UInt32, const AURenderCallbackStruct *); CP_AUDIO_NATIVE("AUGraphSetNodeInputCallback", Fn)
    CPAudioGraph *value; @synchronized(CPGraphs) { value = CPGraphs[[NSValue valueWithPointer:graph]]; }
    if (value && callback && callback->inputProc) {
        // Every node/bus receives its own immutable original callback. Retain
        // contexts until native DisposeAUGraph stops all renders, including
        // old callbacks replaced while a graph is active.
        CPAudioCallback *context = [CPAudioCallback new]; context->original = *callback;
        @synchronized(CPGraphs) { [value.renderContexts addObject:context]; }
        AURenderCallbackStruct wrapper = { CPRenderAudio, (__bridge void *)context };
        OSStatus status = native(graph, node, input, &wrapper);
        fprintf(stderr, "CP_AUDIO graph_callback installed=%d status=%d\n", status == noErr, (int)status); return status;
    }
    return native(graph, node, input, callback);
}
OSStatus CPAUGraphStart(AUGraph graph) {
    typedef OSStatus (*Fn)(AUGraph); CP_AUDIO_NATIVE("AUGraphStart", Fn)
    if (!CPAudioActivate()) return CPIllegalOperation;
    OSStatus status = native(graph);
    @synchronized(CPGraphs) { CPAudioGraph *value = CPGraphs[[NSValue valueWithPointer:graph]]; value.wantedRunning = status == noErr; value.paused = NO; }
    fprintf(stderr, "CP_AUDIO graph_start status=%d\n", (int)status); return status;
}
OSStatus CPAUGraphStop(AUGraph graph) {
    typedef OSStatus (*Fn)(AUGraph); CP_AUDIO_NATIVE("AUGraphStop", Fn)
    OSStatus status = native(graph);
    if (!status) @synchronized(CPGraphs) { CPAudioGraph *value = CPGraphs[[NSValue valueWithPointer:graph]]; value.wantedRunning = NO; value.paused = NO; }
    return status;
}
OSStatus CPDisposeAUGraph(AUGraph graph) {
    typedef OSStatus (*Fn)(AUGraph); CP_AUDIO_NATIVE("DisposeAUGraph", Fn)
    OSStatus status = native(graph);
    if (!status) @synchronized(CPGraphs) { [CPGraphs removeObjectForKey:[NSValue valueWithPointer:graph]]; }
    return status;
}
OSStatus CPAudioOutputUnitStart(AudioUnit unit) {
    typedef OSStatus (*Fn)(AudioUnit); CP_AUDIO_NATIVE("AudioOutputUnitStart", Fn)
    if (!CPAudioActivate()) return CPIllegalOperation;
    OSStatus status = native(unit); fprintf(stderr, "CP_AUDIO output_start status=%d\n", (int)status); return status;
}
OSStatus CPAudioOutputUnitStop(AudioUnit unit) {
    typedef OSStatus (*Fn)(AudioUnit); CP_AUDIO_NATIVE("AudioOutputUnitStop", Fn)
    OSStatus status = native(unit); fprintf(stderr, "CP_AUDIO output_stop status=%d\n", (int)status); return status;
}
#undef CP_AUDIO_NATIVE

// AVAudioEngine is already the game's native second output path. These hooks
// observe the real start result and preserve every source-node callback.
static BOOL (*CPOriginalEngineStart)(id, SEL, NSError **);
static BOOL CPObserveEngineStart(id engine, SEL selector, NSError **error) {
    if (!CPAudioActivate()) { if (error) *error = CPAudioSessionError; return NO; }
    BOOL result = CPOriginalEngineStart(engine, selector, error);
    fprintf(stderr, "CP_AUDIO avengine_start success=%d running=%d error=%s\n", result, [engine isRunning], error && *error ? (*error).description.UTF8String : "none");
    return result;
}
static id (*CPOriginalSourceInit)(id, SEL, AVAudioSourceNodeRenderBlock);
static id (*CPOriginalSourceFormatInit)(id, SEL, AVAudioFormat *, AVAudioSourceNodeRenderBlock);
static AVAudioSourceNodeRenderBlock CPObserveSource(AVAudioSourceNodeRenderBlock original) {
    if (!original) return nil;
    return [^OSStatus(BOOL *silence, const AudioTimeStamp *time, AVAudioFrameCount frames, AudioBufferList *buffers) {
        OSStatus status = original(silence, time, frames, buffers);
        CPCountPCM(status, buffers); return status;
    } copy];
}
static _Thread_local BOOL CPSourceConstructing;
static id CPSourceInit(id node, SEL selector, AVAudioSourceNodeRenderBlock block) {
    BOOL previous = CPSourceConstructing; CPSourceConstructing = YES;
    id result = CPOriginalSourceInit(node, selector, previous ? block : CPObserveSource(block));
    CPSourceConstructing = previous; return result;
}
static id CPSourceFormatInit(id node, SEL selector, AVAudioFormat *format, AVAudioSourceNodeRenderBlock block) {
    BOOL previous = CPSourceConstructing; CPSourceConstructing = YES;
    id result = CPOriginalSourceFormatInit(node, selector, format, previous ? block : CPObserveSource(block));
    CPSourceConstructing = previous; return result;
}
static void CPPauseAudioGraphs(BOOL paused) {
    typedef OSStatus (*Fn)(AUGraph);
    Fn action = CPAudioSymbol("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", paused ? "AUGraphStop" : "AUGraphStart");
    if (!action || (!paused && !CPAudioActivate())) return;
    @synchronized(CPGraphs) { for (CPAudioGraph *value in CPGraphs.allValues) {
        if (value.wantedRunning && (paused != value.paused)) {
            OSStatus status = action(value.graph);
            if (!status) value.paused = paused;
            fprintf(stderr, "CP_AUDIO graph_lifecycle paused=%d status=%d\n", paused, (int)status);
        }
    } }
}
void CPAudioInitialize(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CPGraphs = [NSMutableDictionary new];
        Method start = class_getInstanceMethod(AVAudioEngine.class, @selector(startAndReturnError:));
        if (start) CPOriginalEngineStart = (void *)method_setImplementation(start, (IMP)CPObserveEngineStart);
        Method init = class_getInstanceMethod(AVAudioSourceNode.class, @selector(initWithRenderBlock:));
        if (init) CPOriginalSourceInit = (void *)method_setImplementation(init, (IMP)CPSourceInit);
        Method format = class_getInstanceMethod(AVAudioSourceNode.class, @selector(initWithFormat:renderBlock:));
        if (format) CPOriginalSourceFormatInit = (void *)method_setImplementation(format, (IMP)CPSourceFormatInit);
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification *notification) { CPPauseAudioGraphs(YES); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *notification) { CPPauseAudioGraphs(NO); }];
        [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:nil usingBlock:^(NSNotification *notification) { CPPauseAudioGraphs([notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan); }];
        CPMeter = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        dispatch_source_set_timer(CPMeter, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(CPMeter, ^{ fprintf(stderr, "CP_AUDIO pcm callbacks=%llu nonzero=%llu errors=%u\n", atomic_load(&CPCallbacks), atomic_load(&CPNonzeroCallbacks), atomic_load(&CPRenderErrors)); });
        dispatch_resume(CPMeter);
        CPAudioActivate();
    });
}
__attribute__((constructor)) static void CPInstallAudio(void) { @autoreleasepool { CPAudioInitialize(); } }
