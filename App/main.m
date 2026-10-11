#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Metal/Metal.h>
#import <AVFAudio/AVFAudio.h>
#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>
#import "GameEngineAudit.h"
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <errno.h>
#import <stdatomic.h>
#import "HostDiagnostics.h"
#import "DisplayPolicy.h"
#import "PerformanceProfile.h"
#import "LaunchMenu.h"
#import "compat/UILanguage.h"

static NSString *CPHostBundlePath;
static NSDictionary *CPGuestMetadata;
static void *CPCompatHandle, *CPGuestHandle;
static NSMutableArray<NSValue *> *CPLibraryHandles;
static atomic_bool CPGuestEntryStarted;
static atomic_bool CPGuestEntryReturned;
static BOOL CPLaunchAttempted;
static NSThread *CPGuestThread;
static void (*CPSetAppKitActive)(BOOL);
static void (*CPSetMetalActive)(BOOL);
static void (*CPGuestControllersLoaded)(void);
static NSDictionary *(*CPAppKitReport)(void);
static NSDictionary *(*CPControllerReport)(void);
static NSDictionary *(*CPMetalReport)(void);

static BOOL CPOption(NSString *argument, const char *environment) {
    const char *value = getenv(environment);
    return [NSProcessInfo.processInfo.arguments containsObject:argument] ||
           (value && (!strcmp(value, "1") || !strcasecmp(value, "true") || !strcasecmp(value, "yes")));
}

@interface CPHostViewController : UIViewController
- (void)showFailure:(NSString *)message;
@end
@implementation CPHostViewController
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = UIColor.blackColor; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationLandscapeRight; }
- (void)showFailure:(NSString *)message {
    UILabel *label = [UILabel new]; label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textColor = UIColor.whiteColor; label.numberOfLines = 0; label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:18];
    label.text = [NSString stringWithFormat:@"赛博朋克2077 启动失败\n\n%@\n\n诊断已保存到 Documents/probe-report.json", message];
    [self.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[ [label.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
                                              [label.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],
                                              [label.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24] ]];
}
@end

static void CPFail(UIWindow *window, NSString *stage, NSString *message) {
    CPHostReportFailure(stage, message);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = window.rootViewController;
        if ([root isKindOfClass:CPHostViewController.class]) [(CPHostViewController *)root showFailure:message];
    });
}

static NSString *CPSelectGameRoot(void) {
    const char *override = getenv("CPGAME_ROOT");
    if (override && strlen(override)) return [@(override) stringByStandardizingPath];
    NSString *external = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/GuestGame"];
    BOOL directory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:external isDirectory:&directory] && directory) return external;
    return [CPHostBundlePath stringByAppendingPathComponent:@"GameData"];
}

static NSArray *CPMissingResources(NSString *root) {
    NSMutableArray *missing = [NSMutableArray new];
    NSArray *files = CPGuestMetadata[@"files"];
    if (![files isKindOfClass:NSArray.class] || files.count == 0)
        return @[@{ @"path": @"guest.json/files", @"reason": @"Resource manifest is absent or empty" }];
    for (NSDictionary *item in files) {
        if (![item isKindOfClass:NSDictionary.class] || [item[@"required"] isEqual:@NO]) continue;
        NSString *relative = item[@"path"];
        if (![relative isKindOfClass:NSString.class] || [relative hasPrefix:@"/"] || [[relative pathComponents] containsObject:@".."]) {
            [missing addObject:@{ @"path": relative ?: @"invalid", @"reason": @"Invalid relative resource path" }]; continue;
        }
        NSError *error = nil;
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:[root stringByAppendingPathComponent:relative] error:&error];
        unsigned long long expected = [item[@"size"] unsignedLongLongValue];
        if (!attributes || (expected && attributes.fileSize != expected))
            [missing addObject:@{ @"path": relative, @"reason": attributes ? @"Size mismatch" : error.localizedDescription ?: @"Missing file",
                                  @"expectedSize": @(expected), @"actualSize": attributes ? @(attributes.fileSize) : NSNull.null }];
    }
    return missing;
}

static BOOL CPValidateGuestEntry(uintptr_t *entryAddress, NSString **error) {
    NSNumber *offsetNumber = CPGuestMetadata[@"entryOffset"]; NSString *uuid = CPGuestMetadata[@"uuid"];
    if (![offsetNumber isKindOfClass:NSNumber.class] || ![uuid isKindOfClass:NSString.class]) {
        *error = @"guest.json does not contain an audited entryOffset and UUID"; return NO;
    }
    uint64_t offset = offsetNumber.unsignedLongLongValue;
    for (uint32_t image = 0; image < _dyld_image_count(); image++) {
        const char *path = _dyld_get_image_name(image);
        if (!path || ![@(path).lastPathComponent isEqualToString:@"CyberpunkGuest.dylib"]) continue;
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(image);
        if (header->magic != MH_MAGIC_64 || header->sizeofcmds > 1024 * 1024) { *error = @"Guest has an invalid Mach-O header"; return NO; }
        const uint8_t *cursor = (const void *)(header + 1), *end = cursor + header->sizeofcmds;
        BOOL uuidAccepted = NO, executableOffset = NO;
        for (uint32_t i = 0; i < header->ncmds; i++) {
            if (cursor + sizeof(struct load_command) > end) { *error = @"Guest load commands exceed their bounds"; return NO; }
            const struct load_command *command = (const void *)cursor;
            if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > end) { *error = @"Guest load-command size is invalid"; return NO; }
            if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
                const struct uuid_command *uuidCommand = (const void *)command;
                uuidAccepted = [[[[NSUUID alloc] initWithUUIDBytes:uuidCommand->uuid] UUIDString] caseInsensitiveCompare:uuid] == NSOrderedSame;
            }
            if (command->cmd == LC_SEGMENT_64 && command->cmdsize >= sizeof(struct segment_command_64)) {
                const struct segment_command_64 *segment = (const void *)command;
                if (!strncmp(segment->segname, "__TEXT", 16) && segment->fileoff == 0 &&
                    command->cmdsize >= sizeof(*segment) + segment->nsects * sizeof(struct section_64)) {
                    const struct section_64 *sections = (const void *)(segment + 1);
                    for (uint32_t section = 0; section < segment->nsects; section++) {
                        const struct section_64 *text = &sections[section];
                        if (!strncmp(text->sectname, "__text", 16) && offset >= text->offset && offset - text->offset < text->size && (offset & 3) == 0)
                            executableOffset = YES;
                    }
                }
            }
            cursor += command->cmdsize;
        }
        if (!uuidAccepted || !executableOffset) { *error = @"Guest UUID or entryOffset does not match its executable instruction section"; return NO; }
        *entryAddress = (uintptr_t)header + offset;
        Dl_info addressInfo = {0};
        if (!dladdr((const void *)*entryAddress, &addressInfo) || addressInfo.dli_fbase != header) { *error = @"Entry address did not resolve into the loaded guest image"; return NO; }
        CPHostRecordEvent(@"guestEntryAudit", @{ @"uuid": uuid, @"entryOffset": @(offset), @"address": [NSString stringWithFormat:@"0x%llx", (unsigned long long)*entryAddress], @"executableSectionAccepted": @YES });
        CPHostRecordEvent(@"gameEnginePatch",CPGameEnginePatchAudit(header));
        return YES;
    }
    *error = @"Loaded CyberpunkGuest.dylib was not present in the dyld image list"; return NO;
}

static BOOL CPLoadImage(NSString *path, NSString *label, UIWindow *window, void **result) {
    dlerror(); void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        const char *failure = dlerror(); NSString *message = failure ? @(failure) : @"dyld returned no error description";
        CPFail(window, label, message); return NO;
    }
    [CPLibraryHandles addObject:[NSValue valueWithPointer:handle]];
    CPHostRecordEvent(label, @{ @"loaded": @YES, @"path": path });
    if (result) *result = handle;
    return YES;
}

static void CPTestShaders(NSString *root) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    NSMutableArray *reports = [NSMutableArray new];
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:[root stringByAppendingPathComponent:@"engine"]];
    for (NSString *relative in enumerator) {
        if (![relative.pathExtension isEqualToString:@"metallib"]) continue;
        NSString *path = [[root stringByAppendingPathComponent:@"engine"] stringByAppendingPathComponent:relative];
        NSError *error = nil; id<MTLLibrary> library = [device newLibraryWithURL:[NSURL fileURLWithPath:path] error:&error];
        [reports addObject:@{ @"path": path, @"loaded": @(library != nil), @"functionCount": library ? @(library.functionNames.count) : @0,
                             @"error": error.localizedDescription ?: NSNull.null, @"pipelinesVerified": @NO }];
    }
    CPHostRecordEvent(@"shaderLibraryTests", @{ @"device": device.name ?: @"unavailable", @"libraries": reports,
                                               @"noStaticLibrariesFound": @(reports.count == 0), @"gameRenderingVerified": @NO });
}

@interface CPGameBootstrap : NSObject
@property(nonatomic) uintptr_t entryAddress;
@property(nonatomic, strong) UIWindow *hostWindow;
@property(nonatomic, copy) NSArray<NSString *> *arguments;
- (void)run;
@end
@implementation CPGameBootstrap
- (void)run {
    @autoreleasepool {
        BOOL expected = NO;
        if (!atomic_compare_exchange_strong(&CPGuestEntryStarted, &expected, YES)) {
            CPHostReportFailure(@"guest_entry", @"An entry call was already made in this process"); return;
        }
        int count = (int)self.arguments.count; char **arguments = calloc((size_t)count + 1, sizeof(char *));
        if (!arguments) { CPFail(self.hostWindow, @"guest_entry", @"Failed to allocate native entry arguments"); return; }
        for (int i = 0; i < count; i++) {
            arguments[i] = strdup(self.arguments[(NSUInteger)i].UTF8String);
            if (!arguments[i]) {
                for (int j = 0; j < i; j++) free(arguments[j]); free(arguments);
                CPFail(self.hostWindow, @"guest_entry", @"Failed to copy native entry arguments"); return;
            }
        }
        CPHostRecordEvent(@"guestEntryCalled", @{ @"stackBytes": @(NSThread.currentThread.stackSize), @"arguments": self.arguments, @"count": @1 });
        CPHostRecordEvent(@"launchState", @"original_game_entry_running");
        int (*guestMain)(int, char **, char **, char **) = (void *)self.entryAddress;
        extern char **environ;
        char *apple[] = { arguments[0], NULL };
        int result = guestMain(count, arguments, environ, apple);
        atomic_store(&CPGuestEntryReturned,YES);
        void (*stopControllers)(void)=dlsym(CPCompatHandle,"CPControllersGuestStopped");
        void (*stopAppKit)(void)=dlsym(CPCompatHandle,"CPAppKitGuestStopped");
        if(stopControllers)stopControllers();
        if(stopAppKit)stopAppKit();
        for (int i = 0; i < count; i++) free(arguments[i]); free(arguments);
        CPHostRecordEvent(@"guestEntryReturned", @(result));
        if(result)CPFail(self.hostWindow, @"guest_entry_returned", [NSString stringWithFormat:@"游戏入口返回错误 %d。", result]);
        else {
            CPHostRecordEvent(@"launchState",@"original_game_exited_normally");
            dispatch_async(dispatch_get_main_queue(),^{
                CPHostViewController *view=[CPHostViewController new];self.hostWindow.rootViewController=view;
                UILabel *label=[UILabel new];label.frame=view.view.bounds;label.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
                label.text=@"游戏已退出\n重新启动应用可继续游玩";label.numberOfLines=0;label.textAlignment=NSTextAlignmentCenter;label.textColor=UIColor.whiteColor;[view.view addSubview:label];
            });
        }
    }
}
@end

static void CPLaunch(UIWindow *window) {
    if (CPLaunchAttempted) return;
    CPLaunchAttempted = YES;
    CPHostRecordEvent(@"launchState", @"preparing");
    NSData *metadata = [NSData dataWithContentsOfFile:[CPHostBundlePath stringByAppendingPathComponent:@"guest.json"]];
    NSError *error = nil;
    id parsed = metadata ? [NSJSONSerialization JSONObjectWithData:metadata options:0 error:&error] : nil;
    if (![parsed isKindOfClass:NSDictionary.class]) { CPFail(window, @"metadata", error.localizedDescription ?: @"guest.json missing or invalid"); return; }
    CPGuestMetadata = parsed;
    CPHostRecordEvent(@"guestMetadata", CPGuestMetadata);
    BOOL loadOnly = CPOption(@"--load-only", "CP_LOAD_ONLY"), testShaders = CPOption(@"--test-shaders", "CP_TEST_SHADERS");
    NSString *root = CPSelectGameRoot();
    setenv("CPGAME_ROOT", root.fileSystemRepresentation, 1);
    CPHostRecordEvent(@"gameRoot", root);
    NSArray *missing = CPMissingResources(root);
    CPHostRecordEvent(@"resourcePreflight", @{ @"check": @"presence_and_size", @"hashesVerifiedOnDevice": @NO,
                                              @"missingCount": @(missing.count), @"missing": missing });
    if (missing.count && !loadOnly && !testShaders) {
        CPFail(window, @"resources", [NSString stringWithFormat:@"缺少或大小不符的游戏资源：%lu 项。请将匹配版本的 archive、engine、r6 导入 Documents/GuestGame。首项：%@", (unsigned long)missing.count, missing.firstObject[@"path"]]); return;
    }
    if(!CPPreparePerformanceFiles(root,&error) || !CPApplyDisplayPolicy(window,&error)) {
        CPFail(window,@"performance_profile",error.localizedDescription ?: @"Performance configuration could not be prepared; existing settings backup retained");return;
    }
    CPSetHDRBootstrap(window);
    if (chdir(root.fileSystemRepresentation) != 0) {
        CPFail(window, @"game_root", [NSString stringWithFormat:@"Cannot access game resource root: %s", strerror(errno)]); return;
    }
    NSString *frameworks = [CPHostBundlePath stringByAppendingPathComponent:@"Frameworks"];
    CPLibraryHandles = [NSMutableArray new];
    if (!CPLoadImage([frameworks stringByAppendingPathComponent:@"libCPCompat.dylib"], @"compatibilityImage", window, &CPCompatHandle)) return;
    BOOL (*prepareWritable)(NSError **) = dlsym(CPCompatHandle,"CPPrepareGuestWritableDirectories");
    NSError *writableError=nil;
    if(!prepareWritable || !prepareWritable(&writableError)) {
        CPFail(window,@"writable_directories",writableError.localizedDescription ?: @"Writable game-directory adapter is unavailable");return;
    }
    CPHostRecordEvent(@"writableDirectoriesPrepared",@YES);
    void (*bindWindow)(UIWindow *) = dlsym(CPCompatHandle, "CPAppKitBindHostWindow");
    if (!bindWindow) { CPFail(window, @"window_bridge", @"Compatibility image does not export CPAppKitBindHostWindow"); return; }
    bindWindow(window);
    CPSetAppKitActive = dlsym(CPCompatHandle, "CPAppKitSetApplicationActive");
    CPSetMetalActive = dlsym(CPCompatHandle, "CPMetalSetApplicationActive");
    CPAppKitReport = dlsym(CPCompatHandle, "CPAppKitRuntimeReport");
    CPControllerReport = dlsym(CPCompatHandle, "CPControllerRuntimeReport");
    CPMetalReport = dlsym(CPCompatHandle, "CPMetalRuntimeReport");
    void (*installControllers)(CPHostLogger, BOOL) = dlsym(CPCompatHandle, "CPInstallControllers");
    void (*installMetal)(CPHostLogger) = dlsym(CPCompatHandle, "CPInstallMetalLifecycle");
    CPGuestControllersLoaded = dlsym(CPCompatHandle, "CPControllersGuestLoaded");
    if (installControllers) installControllers(CPHostRecordEvent, CPOption(@"--trace-controller", "CP_TRACE_CONTROLLER"));
    if (installMetal) installMetal(CPHostRecordEvent);
    CPHostRecordEvent(@"hostAdapters", @{ @"controllersExported": @(installControllers != NULL), @"metalLifecycleExported": @(installMetal != NULL), @"applicationLifecycleExported": @(CPSetAppKitActive != NULL) });
    AVAudioSession *audio = AVAudioSession.sharedInstance;
    NSError *audioError = nil; BOOL category = [audio setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&audioError];
    BOOL active = category && [audio setActive:YES error:&audioError];
    CPHostRecordEvent(@"audioSession", @{ @"active": @(active), @"sampleRate": @(audio.sampleRate), @"outputChannels": @(audio.outputNumberOfChannels), @"route": audio.currentRoute.description, @"error": audioError.localizedDescription ?: NSNull.null, @"audibleGameOutputVerified": @NO });
    if (testShaders) CPTestShaders(root);
    CPHostStartPerformanceTrace(MTLCreateSystemDefaultDevice(),CPMetalReport,CPOption(@"--trace-memory", "CP_TRACE_MEMORY"));
    NSArray *libraries = CPGuestMetadata[@"libraries"];
    if (![libraries isKindOfClass:NSArray.class]) libraries = @[@"libBink2MacArm64.dylib", @"libGameServicesSteam.dylib", @"libREDGalaxy64.dylib", @"libsteam_api.dylib"];
    for (NSString *library in libraries) {
        if (![library isKindOfClass:NSString.class] || ![library.lastPathComponent isEqualToString:library]) { CPFail(window, @"library_metadata", @"Invalid guest library name"); return; }
        if (!CPLoadImage([frameworks stringByAppendingPathComponent:library], [@"guestLibrary/" stringByAppendingString:library], window, NULL)) return;
    }
    if (!CPLoadImage([frameworks stringByAppendingPathComponent:@"CyberpunkGuest.dylib"], @"guestImage", window, &CPGuestHandle)) return;
    uintptr_t entry = 0; NSString *entryError = nil;
    if (!CPValidateGuestEntry(&entry, &entryError)) { CPFail(window, @"guest_entry_audit", entryError); return; }
    if (CPGuestControllersLoaded) CPGuestControllersLoaded();
    if (CPSetAppKitActive) CPSetAppKitActive(YES);
    if (CPSetMetalActive) CPSetMetalActive(YES);
    if (CPAppKitReport) CPHostRecordEvent(@"appKitBridge", CPAppKitReport());
    if (loadOnly || testShaders) {
        CPHostRecordEvent(@"launchState", @"load_only_complete");
        CPHostRecordEvent(@"guestEntryCalled", @NO);
        return;
    }
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObject:@"Cyberpunk2077"];
    NSArray *extra = CPGuestMetadata[@"arguments"];
    if ([extra isKindOfClass:NSArray.class]) for (id item in extra) if ([item isKindOfClass:NSString.class]) [arguments addObject:item];
    CPGameBootstrap *bootstrap = [CPGameBootstrap new]; bootstrap.entryAddress = entry; bootstrap.hostWindow = window; bootstrap.arguments = arguments;
    CPGuestThread = [[NSThread alloc] initWithTarget:bootstrap selector:@selector(run) object:nil];
    CPGuestThread.name = @"Cyberpunk original ARM64 entry"; CPGuestThread.stackSize = 8 * 1024 * 1024;
    CPGuestThread.qualityOfService = NSQualityOfServiceUserInitiated; [CPGuestThread start];
    // Ordinary frame/memory and engine-parameter sampling use the utility
    // report queue. UIKit hierarchy/EDR/controller snapshots are diagnostic
    // launch only; never make the normal render loop wait for periodic UI work.
    if(CPOption(@"--trace-runtime","CP_TRACE_RUNTIME"))
        [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:YES block:^(__unused NSTimer *timer) {
            if (CPAppKitReport) CPHostRecordEvent(@"appKitBridge", CPAppKitReport());
            if (CPControllerReport) CPHostRecordEvent(@"controllerRuntime", CPControllerReport());
        }];
}

@interface CPSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation CPSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    if(CPOption(@"--load-only","CP_LOAD_ONLY") || CPOption(@"--test-shaders","CP_TEST_SHADERS"))self.window.rootViewController=[CPHostViewController new];
    else {
        CPLaunchMenu *menu=[CPLaunchMenu new];__weak CPSceneDelegate *weak=self;
        menu.startGame=^{CPSceneDelegate *owner=weak;if(!owner || CPLaunchAttempted)return;
            owner.window.rootViewController=[CPHostViewController new];CPLaunch(owner.window);};
        self.window.rootViewController=menu;
    }
    [self.window makeKeyAndVisible];
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    if (!atomic_load(&CPGuestEntryReturned) && CPSetAppKitActive) CPSetAppKitActive(YES);
    if (!atomic_load(&CPGuestEntryReturned) && CPSetMetalActive) CPSetMetalActive(YES);
    if (!CPLaunchAttempted && [self.window.rootViewController isKindOfClass:CPHostViewController.class]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (scene.activationState == UISceneActivationStateForegroundActive) CPLaunch(self.window); });
}
- (void)sceneWillResignActive:(UIScene *)scene {
    if (!atomic_load(&CPGuestEntryReturned) && CPSetAppKitActive) CPSetAppKitActive(NO);
    if (!atomic_load(&CPGuestEntryReturned) && CPSetMetalActive) CPSetMetalActive(NO);
    CPHostRecordEvent(@"uiSceneActive", @NO);
}
- (void)sceneDidEnterBackground:(UIScene *)scene { CPHostRecordEvent(@"uiSceneState", @"background"); }
@end

@interface CPAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation CPAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    CPHostDiagnosticsInitialize(@{ @"hostBundle": CPHostBundlePath, @"targetDevice": @"iPhone 16 Pro Max", @"guestEntryCalled": @NO });
    CPHostRecordEvent(@"hostLaunch", @"UIKit scene host started");
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Cyberpunk" sessionRole:session.role];
    configuration.delegateClass = CPSceneDelegate.class; return configuration;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        CFURLRef url = CFBundleCopyBundleURL(CFBundleGetMainBundle());
        CPHostBundlePath = [((__bridge NSURL *)url).path copy]; CFRelease(url);
        setenv("CP_HOST_BUNDLE", CPHostBundlePath.fileSystemRepresentation, 1);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(CPAppDelegate.class));
    }
}
