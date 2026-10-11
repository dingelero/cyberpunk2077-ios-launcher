#import "PerformanceProfile.h"
#import "HostDiagnostics.h"
#import "GameJSON.h"
#import "LaunchPreferences.h"
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <TargetConditionals.h>
#include <math.h>
#include <stdlib.h>
#if !TARGET_OS_SIMULATOR
#import <MetalFX/MetalFX.h>
#endif

static NSUInteger CPDRSMinimum = 50;
static NSDictionary *CPProfile;
NSUInteger CPPerformanceDRSMinimum(void) { return CPDRSMinimum; }
NSUInteger CPPerformanceDRSMaximum(void) {return [CPProfile[@"DRSMaximum"] unsignedIntegerValue] ?: 50;}
NSDictionary *CPPerformanceDeviceProfile(void) {return CPProfile;}

BOOL CPPreparePerformanceFiles(NSString *gameRoot, NSError **error) {
    NSString *bundle=NSBundle.mainBundle.bundlePath;
    NSString *template=[bundle stringByAppendingPathComponent:@"PerformanceProfile"];
    NSString *destination=[[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/PerformanceOverrides"] stringByAppendingPathComponent:CP_PERFORMANCE_VERSION];
    if(![NSFileManager.defaultManager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:error])return NO;
    NSData *raw=[NSData dataWithContentsOfFile:[template stringByAppendingPathComponent:@"options.json"] options:0 error:error];
    NSMutableDictionary *schema=raw?[NSJSONSerialization JSONObjectWithData:raw options:NSJSONReadingMutableContainers error:error]:nil;
    if(!schema || ![schema[@"options"] isKindOfClass:NSArray.class])return NO;
    float maximumScale=0;BOOL temporalSupported=NO;
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    CPProfile=CPResolveLaunchProfile(CPLoadLaunchPreferences(),device.name,UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad);
    CPDRSMinimum=50;
#if !TARGET_OS_SIMULATOR
    if(@available(iOS 17.0,*)) {
        temporalSupported=[MTLFXTemporalScalerDescriptor supportsDevice:device];
        if(temporalSupported)maximumScale=[MTLFXTemporalScalerDescriptor supportedInputContentMaxScaleForDevice:device];
    }
#endif
    // Keep the lower bound inside the native scaler's advertised range. If
    // no reliable range is available, retain the original 50 percent floor.
    if(temporalSupported && isfinite(maximumScale) && maximumScale>=2.0f)
        CPDRSMinimum=MAX([CPProfile[@"DRSMinimum"] unsignedIntegerValue],(NSUInteger)ceil(100.0/maximumScale));
    unsigned found=0;
    for(NSMutableDictionary *group in schema[@"options"])for(NSMutableDictionary *option in group[@"options"]) {
        if([option[@"name"] isEqual:@"DRS_MinResolution"] || [option[@"name"] isEqual:@"DRS_MaxResolution"]) {
            if(![option[@"min_value"] isEqual:@50]) {
                if(error)*error=[NSError errorWithDomain:@"CPPerformanceProfile" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Unexpected original DRS bounds"}];return NO;
            }
            option[@"min_value"]=@(CPDRSMinimum);found++;
        }
    }
    if(found!=2)return NO;
    NSData *options=CPGameJSONData(schema,error);
    NSData *rendering=[NSData dataWithContentsOfFile:[template stringByAppendingPathComponent:@"rendering.ini"] options:0 error:error];
    if(!options || !rendering)return NO;
    // Exact-file redirects preserve original directory enumeration and other
    // config files. Original imported resources remain intact and re-importable.
    if(![options writeToFile:[destination stringByAppendingPathComponent:@"options.json"] options:NSDataWritingAtomic error:error] ||
       ![rendering writeToFile:[destination stringByAppendingPathComponent:@"rendering.ini"] options:NSDataWritingAtomic error:error])return NO;
    setenv("CP2077_PERFORMANCE_PROFILE_ROOT",destination.fileSystemRepresentation,1);
    NSDictionary *report=@{@"version":CP_PERFORMANCE_VERSION,@"nativeTemporalSupported":@(temporalSupported),
        @"nativeMaximumContentScale":@(maximumScale),@"DRSMinimumPercent":@(CPDRSMinimum),@"DRSMaximumPercent":@(CPPerformanceDRSMaximum()),
        @"deviceProfile":CPProfile,@"nativeGPUName":device.name ?: @"unavailable",@"physicalMemoryBytes":@(NSProcessInfo.processInfo.physicalMemory),
        @"nodeAttachmentBudget":@192,@"nodeLoadingBudgetUnchanged":@YES,@"independentFPSLimiterDefault":@NO,
        @"HDDModeDefault":@"Off",@"ordinaryMainThreadPeriodicDiagnostics":@NO,
        @"resourceCacheExpiryOverride":NSNull.null,@"resourceRetentionPolicy":@"native engine defaults",@"originalResourcesModified":@NO,@"directoryEnumerationPreserved":@YES,
        @"configurationApplicationVerified":@NO,@"sustained30FPSVerified":@NO};
    CPHostRecordEvent(@"gamePerformanceFiles",report);
    NSData *receipt=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:error];
    return receipt && [receipt writeToFile:[destination stringByAppendingPathComponent:@"profile-report.json"] options:NSDataWritingAtomic error:error];
}
