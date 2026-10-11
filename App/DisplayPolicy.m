#import "DisplayPolicy.h"
#import "HostDiagnostics.h"
#import "PerformanceProfile.h"
#import "GameJSON.h"
#import "GamePacing.h"
#import "LaunchPreferences.h"
#import <QuartzCore/QuartzCore.h>

static NSString *const CPPolicyVersion=CP_PERFORMANCE_VERSION;
static NSString *CPSettingsPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/CD Projekt Red/Cyberpunk 2077/UserSettings.json"];
}
static id CPReadSetting(NSDictionary *settings,NSString *name) {
    if(![settings[@"data"] isKindOfClass:NSArray.class])return nil;
    for(id group in settings[@"data"]) {
        if(![group isKindOfClass:NSDictionary.class] || ![group[@"options"] isKindOfClass:NSArray.class])continue;
        for(id option in group[@"options"])if([option isKindOfClass:NSDictionary.class] && [option[@"name"] isEqual:name])return option[@"value"];
    }
    return nil;
}
void CPSetHDRBootstrap(UIWindow *window) {
    NSData *data=[NSData dataWithContentsOfFile:CPSettingsPath()];
    NSDictionary *settings=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    id mode=[settings isKindOfClass:NSDictionary.class]?CPReadSetting(settings,@"HDRModes"):nil;
    BOOL requested=[mode isKindOfClass:NSString.class] && [mode hasPrefix:@"HDR10"];
    setenv("CP2077_HDR_REQUESTED",requested?"1":"0",1);
    // Request real EDR before the macOS renderer queries current headroom.
    // iOS may report 1 until an onscreen context requests EDR. No screen or
    // GPU capability getter is replaced; the game still chooses its format.
    window.rootViewController.view.layer.wantsExtendedDynamicRangeContent=requested;
    [CATransaction flush];
    CPHostRecordEvent(@"hdrBootstrap",@{@"requested":@(requested),@"nativeCurrentHeadroom":@(window.screen.currentEDRHeadroom),
        @"nativePotentialHeadroom":@(window.screen.potentialEDRHeadroom),@"hardwareEffectVerified":@NO});
}
BOOL CPApplyDisplayPolicy(UIWindow *window,NSError **error) {
    NSString *path=CPSettingsPath();NSData *data=[NSData dataWithContentsOfFile:path];BOOL fresh=data==nil;
    id settings;
    if(data)settings=[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error];
    else {
        NSData *raw=[NSData dataWithContentsOfFile:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"PerformanceProfile/options.json"] options:0 error:error];
        NSDictionary *schema=raw?[NSJSONSerialization JSONObjectWithData:raw options:0 error:error]:nil;
        settings=schema?CPInitialMobileSettings(schema,error):nil;
    }
    if(![settings isKindOfClass:NSMutableDictionary.class] || ![settings[@"data"] isKindOfClass:NSArray.class])return NO;
    for(id group in settings[@"data"]) {
        if(![group isKindOfClass:NSDictionary.class] || ![group[@"options"] isKindOfClass:NSArray.class])return NO;
        for(id option in group[@"options"])if(![option isKindOfClass:NSDictionary.class])return NO;
    }
    NSString *marker=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/display-policy-version.txt"];
    NSString *old=[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:NULL];
    NSDictionary *profile=CPPerformanceDeviceProfile();
    CGSize size=CPOutputRenderSize(window.screen.bounds.size,[profile[@"outputHeight"] unsignedIntegerValue]);
    if(CGSizeEqualToSize(size,CGSizeZero))return NO;
    NSString *policyKey=CPDisplayPolicyKey(CPPolicyVersion,profile,size,CPPerformanceDRSMinimum());
    if(!fresh && [old isEqual:policyKey]){CPHostRecordEvent(@"displayPolicy",@{@"version":CPPolicyVersion,@"policyKey":policyKey,@"deviceProfile":profile,@"settingsChanged":@NO,
        @"resolution":CPReadSetting(settings,@"Resolution") ?: NSNull.null,@"frameGeneration":CPReadSetting(settings,@"FrameGeneration") ?: NSNull.null,
        @"FSR3FrameGenerationEnabled":CPReadSetting(settings,@"FSR3_FrameGeneration") ?: NSNull.null,
        @"resolutionScaling":CPReadSetting(settings,@"ResolutionScaling") ?: NSNull.null,
        @"independentFPSLimiterEnabled":CPReadSetting(settings,@"MaximumFPS_OnOff") ?: NSNull.null,
        @"independentFPSLimitValue":CPReadSetting(settings,@"MaximumFPS_Value") ?: NSNull.null,
        @"VSync":CPReadSetting(settings,@"VSync") ?: NSNull.null,@"HDDMode":CPReadSetting(settings,@"HDDMode") ?: NSNull.null,
        @"DRSMinimumPercent":CPReadSetting(settings,@"DRS_MinResolution") ?: NSNull.null,
        @"DRSMaximumPercent":CPReadSetting(settings,@"DRS_MaxResolution") ?: NSNull.null});return YES;}
    NSString *resolution=[NSString stringWithFormat:@"%.0fx%.0f",size.width,size.height];
    // One-time mobile migration with a complete backup. Keep every option and
    // gameplay/quality/HDR setting. The native display clock replaces the
    // independent FPS limiter; SSD mode avoids an HDD-oriented loading policy.
    // Frame generation remains available later.
    NSMutableArray *changes=[NSMutableArray new];
    if(!CPApplyDevicePacing(settings,resolution,CPPerformanceDRSMinimum(),CPPerformanceDRSMaximum(),changes,error))return NO;
    NSString *backup=[path.stringByDeletingLastPathComponent stringByAppendingPathComponent:[NSString stringWithFormat:@"UserSettings-before-%@.json",CPPolicyVersion]];
    if(![NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error])return NO;
    if(data && ![NSFileManager.defaultManager fileExistsAtPath:backup] && ![data writeToFile:backup options:NSDataWritingAtomic error:error])return NO;
    NSData *updated=CPGameJSONData(settings,error);
    if(!updated || ![updated writeToFile:path options:NSDataWritingAtomic error:error])return NO;
    if(![policyKey writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:error])return NO;
    CPHostRecordEvent(@"displayPolicy",@{@"version":CPPolicyVersion,@"policyKey":policyKey,@"deviceProfile":profile,@"settingsChanged":@YES,@"freshSettingsCreated":@(fresh),@"renderResolution":resolution,@"qualitySettingsPreserved":@YES,
        @"upscalingDefault":@"native MetalFX Dynamic",@"hdrSettingPreserved":@YES,@"frameGenerationDefault":@"Off",@"targetFPS":@30,@"changes":changes,
        @"pacingSource":@"native CAMetalDisplayLink",@"independentFPSLimiterEnabled":@NO,
        @"VSync":CPReadSetting(settings,@"VSync") ?: NSNull.null,@"HDDMode":CPReadSetting(settings,@"HDDMode") ?: NSNull.null,
        @"resolutionScaling":CPReadSetting(settings,@"ResolutionScaling") ?: NSNull.null,
        @"frameGeneration":CPReadSetting(settings,@"FrameGeneration") ?: NSNull.null,@"FSR3FrameGenerationEnabled":CPReadSetting(settings,@"FSR3_FrameGeneration") ?: NSNull.null,
        @"DRSMinimumPercent":CPReadSetting(settings,@"DRS_MinResolution") ?: NSNull.null,
        @"DRSMaximumPercent":CPReadSetting(settings,@"DRS_MaxResolution") ?: NSNull.null,
        @"nativeInternal720pVerified":@NO,@"hdrHardwareVerified":@NO,@"sustainedGameplayFPSVerified":@NO});
    return YES;
}
