#import <Foundation/Foundation.h>
#import "LaunchPreferences.h"
#import "GamePacing.h"
#import "GameJSON.h"
#import "compat/UILanguage.h"
static void Require(BOOL success,NSString *message){if(!success){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
static id Read(NSDictionary *settings,NSString *name){for(NSDictionary *g in settings[@"data"])for(NSDictionary *o in g[@"options"])if([o[@"name"] isEqual:name])return o[@"value"];return nil;}
int main(int argc,char **argv){@autoreleasepool {
    Require(argc==4,@"Schema, real settings, report paths required");NSError *error=nil;
    NSDictionary *schema=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:&error];
    NSData *existing=[NSData dataWithContentsOfFile:@(argv[2])];Require(existing!=nil,@"Existing settings fixture absent");
    NSDictionary *before=[NSJSONSerialization JSONObjectWithData:existing options:0 error:&error];
    NSArray *screens=@[[NSValue valueWithSize:NSMakeSize(2868,1320)],[NSValue valueWithSize:NSMakeSize(2532,1170)],
        [NSValue valueWithSize:NSMakeSize(2732,2048)],[NSValue valueWithSize:NSMakeSize(2360,1640)],
        [NSValue valueWithSize:NSMakeSize(2266,1488)],[NSValue valueWithSize:NSMakeSize(2420,1668)]];
    NSMutableArray *matrix=[NSMutableArray new];NSSet *changed=[NSSet setWithArray:@[@"Resolution",@"MaximumFPS_OnOff",@"MaximumFPS_Value",@"DRS_TargetFPS",@"FrameGeneration",@"FSR3_FrameGeneration",@"ResolutionScaling",@"DynamicResolutionScaling",@"DRS_MinResolution",@"DRS_MaxResolution",@"FSR2",@"VSync",@"HDDMode"]];
    for(NSDictionary *profile in CPDeviceProfiles())for(NSNumber *height in @[@720,@1080])for(NSValue *screen in screens) {
        NSSize frame=screen.sizeValue;CGSize size=CPOutputRenderSize(CGSizeMake(frame.width,frame.height),height.unsignedIntegerValue);
        Require(size.height==height.doubleValue && ((unsigned)size.width%2)==0 && fabs(size.width/size.height-frame.width/frame.height)<=1/size.height,@"Aspect-preserving even output dimensions");
        NSString *resolution=[NSString stringWithFormat:@"%.0fx%.0f",size.width,size.height];
        NSMutableDictionary *fresh=CPInitialMobileSettings(schema,&error);Require(fresh!=nil,@"Fresh settings schema conversion");
        Require(CPApplyDevicePacing(fresh,resolution,[profile[@"DRSMinimum"] unsignedIntegerValue],[profile[@"DRSMaximum"] unsignedIntegerValue],[NSMutableArray new],&error),error.localizedDescription ?: @"Fresh settings application");
        Require([Read(fresh,@"Resolution") isEqual:resolution] && [Read(fresh,@"DRS_MaxResolution") isEqual:profile[@"DRSMaximum"]],@"Selected output/profile ignored");
        Require(CPGameJSONData(fresh,&error)!=nil,@"Fresh typed serialization");
        NSMutableDictionary *value=[NSJSONSerialization JSONObjectWithData:existing options:NSJSONReadingMutableContainers error:&error];
        NSMutableArray *changes=[NSMutableArray new];Require(CPApplyDevicePacing(value,resolution,[profile[@"DRSMinimum"] unsignedIntegerValue],[profile[@"DRSMaximum"] unsignedIntegerValue],changes,&error),@"Existing settings application");
        for(NSUInteger g=0;g<[before[@"data"] count];g++)for(NSUInteger i=0;i<[before[@"data"][g][@"options"] count];i++) {
            NSDictionary *a=before[@"data"][g][@"options"][i],*b=value[@"data"][g][@"options"][i];
            if(![changed containsObject:a[@"name"]])Require([a isEqual:b],@"Existing quality/gameplay/HDR/controller option changed");
        }
        NSMutableArray *again=[NSMutableArray new];Require(CPApplyDevicePacing(value,resolution,[profile[@"DRSMinimum"] unsignedIntegerValue],[profile[@"DRSMaximum"] unsignedIntegerValue],again,&error) && !again.count,@"Profile application not idempotent");
        [matrix addObject:@{@"profile":profile[@"id"],@"height":height,@"screen":NSStringFromSize(frame),@"output":resolution}];
    }
    Require([CPAutomaticDeviceProfile(@"Apple A18 Pro GPU",NO) isEqual:@"phone-a18-plus"],@"A18 Pro detection");
    Require([CPAutomaticDeviceProfile(@"Apple A17 Pro GPU",NO) isEqual:@"phone-a17"],@"A17 Pro detection");
    Require([CPAutomaticDeviceProfile(@"Apple A17 Pro GPU",YES) isEqual:@"tablet-a-series"],@"Mini detection");
    Require([CPAutomaticDeviceProfile(@"Apple M2 GPU",YES) isEqual:@"tablet-m1-m2"],@"M2 detection");
    Require([CPAutomaticDeviceProfile(@"Apple M5 GPU",YES) isEqual:@"tablet-m3-plus"],@"M5 detection");
    Require([CPAutomaticDeviceProfile(@"Unrecognized GPU",YES) isEqual:@"tablet-a-series"],@"Unknown GPU fallback");
    NSDictionary *bad=CPValidatedLaunchPreferences(@{@"schema":@1,@"profile":@"unknown",@"outputHeight":@999});Require([bad[@"profile"] isEqual:@"auto"] && [bad[@"outputHeight"] isEqual:@720],@"Invalid preferences not sanitized");
    NSDictionary *prefs=@{@"schema":@1,@"profile":@"tablet-m3-plus",@"outputHeight":@1080};
    Require([CPValidatedLaunchPreferences([NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:prefs options:0 error:NULL] options:0 error:NULL]) isEqual:prefs],@"Preference round trip");
    NSDictionary *resolved=CPResolveLaunchProfile(prefs,@"unknown",YES);Require([resolved[@"id"] isEqual:@"tablet-m3-plus"] && [resolved[@"outputHeight"] isEqual:@1080],@"Manual profile ignored");
    NSString *key720=CPDisplayPolicyKey(@"test",resolved,CGSizeMake(1564,720),40),*key1080=CPDisplayPolicyKey(@"test",resolved,CGSizeMake(2346,1080),40);
    Require(![key720 isEqual:key1080],@"Resolution change does not invalidate policy marker");
    Require(CGSizeEqualToSize(CPOutputRenderSize(CGSizeZero,720),CGSizeZero),@"Zero screen accepted");
    Require(!CPInitialMobileSettings(@{@"version":@139,@"options":@[]},NULL),@"Unknown settings version accepted");
    NSDictionary *report=@{@"passed":@YES,@"profileCount":@(CPDeviceProfiles().count),@"profileResolutionScreenCases":@(matrix.count),@"matrix":matrix,@"freshDeviceSchemaVersion":@140,@"existingNonPolicyOptionsPreserved":@YES,@"policyIdempotent":@YES,@"deviceDetectionAndFallbackPassed":@YES,@"scope":@"Production profile and settings code on ARM64 Mac; not device gameplay or frame rate",@"physicalDeviceGameplayVerified":@NO};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:@(argv[3]) atomically:YES];printf("Passed %lu profile/resolution/screen cases\n",(unsigned long)matrix.count);
}}
