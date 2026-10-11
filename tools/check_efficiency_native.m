#import <Foundation/Foundation.h>
#import "CoalescedUpdate.h"
#import "PathStrings.h"
#import "GuestPaths.h"
#import "GameJSON.h"
#import "GamePacing.h"
#include <pthread.h>
#include <stdatomic.h>

static void Check(BOOL pass,NSString *message) {if(!pass){fprintf(stderr,"FAIL %s\n",message.UTF8String);exit(1);}}
static void *PathWorker(void *pointer) {
    @autoreleasepool {
        NSUInteger thread=(NSUInteger)pointer;
        for(unsigned i=0;i<5000;i++)@autoreleasepool {
            NSString *input=[NSString stringWithFormat:@"/native/测试/%lu/file-%u",thread,i%4];
            Check([CPGuestPathString(input.UTF8String) isEqual:input],@"Thread-local Unicode path isolation");
        }
    }
    return NULL;
}
static NSDictionary *CheckPaths(void) {
    Check(CPGuestPathString(NULL)==nil && CPGuestPathString("")==nil,@"NULL and empty libc pass-through");
    const char invalid[]={-1,'a',0};Check(CPGuestPathString(invalid)==nil,@"Invalid UTF-8 libc pass-through");
    NSString *longPath=[@"/" stringByPaddingToLength:2048 withString:@"abc/" startingAtIndex:0];
    Check([CPGuestPathString(longPath.UTF8String) isEqual:longPath],@"Long path uncached fallback");
    pthread_t threads[16];
    for(NSUInteger i=0;i<16;i++)Check(pthread_create(&threads[i],NULL,PathWorker,(void *)i)==0,@"Create path stress worker");
    for(unsigned i=0;i<16;i++)pthread_join(threads[i],NULL);
    NSString *unique=[@"cp-v4-check-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:unique];
    setenv("CPGAME_ROOT",root.UTF8String,1);
    NSFileManager *files=NSFileManager.defaultManager;
    NSString *folder=[root stringByAppendingPathComponent:unique];
    Check([files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL],@"Create native path fixture");
    NSString *file=[folder stringByAppendingPathComponent:@"file.bin"];
    [@"original" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *overlay=CPMapGuestPath(CPGuestPathString(file.UTF8String),YES);
    [files removeItemAtPath:overlay error:NULL];
    Check([CPMapGuestPath(CPGuestPathString(file.UTF8String),NO) isEqual:file.stringByStandardizingPath],@"Original before overlay");
    Check([@"changed" writeToFile:overlay atomically:YES encoding:NSUTF8StringEncoding error:NULL],@"Write overlay");
    Check([CPMapGuestPath(CPGuestPathString(file.UTF8String),NO) isEqual:overlay],@"Live overlay creation invalidates no cache");
    [files removeItemAtPath:overlay error:NULL];
    Check([CPMapGuestPath(CPGuestPathString(file.UTF8String),NO) isEqual:file.stringByStandardizingPath],@"Live overlay deletion");
    NSString *oldDirectory=files.currentDirectoryPath;
    Check([files changeCurrentDirectoryPath:folder],@"Change cwd fixture");
    NSString *first=CPMapGuestPath(CPGuestPathString("file.bin"),NO);
    Check([files changeCurrentDirectoryPath:root],@"Change cwd again");
    NSString *second=CPMapGuestPath(CPGuestPathString("file.bin"),NO);
    Check(![first isEqual:second],@"Relative decoded strings keep live cwd");
    [files changeCurrentDirectoryPath:oldDirectory];
    [files removeItemAtPath:overlay.stringByDeletingLastPathComponent error:NULL];
    [files removeItemAtPath:root error:NULL];
    const char *sample="/private/var/mobile/Containers/Data/Application/example/Documents/GuestGame/archive/Mac/content/basegame_1.archive";
    volatile NSUInteger length=0;const unsigned iterations=200000;
    NSTimeInterval start=NSProcessInfo.processInfo.systemUptime;
    for(unsigned i=0;i<iterations;i++)@autoreleasepool{length+=[NSString stringWithUTF8String:sample].length;}
    NSTimeInterval original=NSProcessInfo.processInfo.systemUptime-start;
    start=NSProcessInfo.processInfo.systemUptime;
    for(unsigned i=0;i<iterations;i++)@autoreleasepool{length+=CPGuestPathString(sample).length;}
    NSTimeInterval cached=NSProcessInfo.processInfo.systemUptime-start;
    Check(length>0,@"Consume benchmark output");
    return @{@"passed":@YES,@"concurrentConversions":@80000,@"threads":@16,@"liveOverlayAndCWD":@YES,
        @"originalDecodeSeconds":@(original),@"cachedDecodeSeconds":@(cached),@"iterations":@(iterations),
        @"scope":@"Repeated path-string microbenchmark on this Mac; excludes I/O and game frame time"};
}
static NSDictionary *CheckCoalescing(void) {
    dispatch_queue_t queue=dispatch_queue_create("test.blocked-layout",DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t pause=dispatch_semaphore_create(0);
    dispatch_async(queue,^{dispatch_semaphore_wait(pause,DISPATCH_TIME_FOREVER);});
    static atomic_bool pending;static atomic_ulong requested,observed,runs;
    dispatch_block_t update=^{atomic_store(&observed,atomic_load(&requested));atomic_fetch_add(&runs,1);};
    for(unsigned i=0;i<100000;i++){atomic_fetch_add(&requested,1);CPRequestCoalescedUpdate(&pending,queue,update);}
    Check(atomic_load(&runs)==0,@"Producers completed while layout consumer remained blocked");
    dispatch_semaphore_signal(pause);dispatch_sync(queue,^{});
    Check(atomic_load(&runs)==1 && atomic_load(&observed)==100000,@"100k requests coalesce to current layout");
    CPRequestCoalescedUpdate(&pending,queue,^{
        atomic_fetch_add(&requested,1);
        CPRequestCoalescedUpdate(&pending,queue,update);
    });
    dispatch_sync(queue,^{});dispatch_sync(queue,^{});
    Check(atomic_load(&observed)==100001 && !atomic_load(&pending),@"Request during consumer callback has follow-up");
    dispatch_apply(8,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^(size_t worker){
        for(unsigned i=0;i<5000;i++){atomic_fetch_add(&requested,1);CPRequestCoalescedUpdate(&pending,queue,update);}
    });
    dispatch_sync(queue,^{});
    Check(atomic_load(&observed)==atomic_load(&requested) && !atomic_load(&pending),@"Concurrent last layout request retained");
    return @{@"passed":@YES,@"blockedConsumerRequests":@100000,@"concurrentRequests":@40000,@"noLostFinalUpdate":@YES};
}
static NSDictionary *CheckSettings(NSString *input) {
    NSData *raw=[NSData dataWithContentsOfFile:input];NSError *error=nil;
    NSMutableDictionary *fixture=[NSJSONSerialization JSONObjectWithData:raw options:NSJSONReadingMutableContainers error:&error];
    // Exercise an actual transition and ensure enabled features remain enabled.
    NSDictionary *initial=@{@"Resolution":@"1280x720",@"MaximumFPS_OnOff":@NO,@"MaximumFPS_Value":@60,@"DRS_TargetFPS":@60,
        @"HDRModes":@"HDR10scRGB",@"CrowdDensity":@"High",@"ContactShadows":@YES,@"FacialTangentUpdates":@YES};
    for(NSMutableDictionary *group in fixture[@"data"])for(NSMutableDictionary *option in group[@"options"])
        if(initial[option[@"name"]])option[@"value"]=initial[option[@"name"]];
    raw=CPGameJSONData(fixture,&error);Check(raw!=nil,@"Enabled-feature fixture serialization");
    NSDictionary *before=[NSJSONSerialization JSONObjectWithData:raw options:0 error:&error];
    NSMutableDictionary *after=[NSJSONSerialization JSONObjectWithData:raw options:NSJSONReadingMutableContainers error:&error];
    NSMutableArray *changes=[NSMutableArray new];
    Check(CPApplyGamePacing(after,@"1564x720",changes,&error),error.localizedDescription ?: @"Native pacing settings");
    Check(changes.count==4,@"All four pacing fields exercise a transition");
    NSSet *allowed=[NSSet setWithArray:@[@"Resolution",@"MaximumFPS_OnOff",@"MaximumFPS_Value",@"DRS_TargetFPS"]];
    NSUInteger preserved=0;
    NSArray *groupsBefore=before[@"data"],*groupsAfter=after[@"data"];
    Check(groupsBefore.count==groupsAfter.count,@"No option groups removed");
    for(NSUInteger g=0;g<groupsBefore.count;g++) {
        NSArray *left=groupsBefore[g][@"options"],*right=groupsAfter[g][@"options"];
        Check(left.count==right.count,@"No options removed");
        for(NSUInteger o=0;o<left.count;o++) {
            if(![allowed containsObject:left[o][@"name"]]){Check([left[o] isEqual:right[o]],@"Every other setting retained verbatim");preserved++;}
        }
    }
    NSData *serialized=CPGameJSONData(after,&error);
    Check(serialized!=nil,@"Typed float JSON serialization");
    NSDictionary *readback=[NSJSONSerialization JSONObjectWithData:serialized options:0 error:&error];
    Check([after isEqual:readback],@"Pacing JSON numeric and option values survive serialization");
    return @{@"passed":@YES,@"otherOptionsPreserved":@(preserved),@"changedSettings":changes,
        @"fixtureWithHDROnAndHighCrowdPreserved":@YES,@"gameplayQARequired":@YES};
}
int main(int argc,const char *argv[]) {@autoreleasepool {
    Check(argc==2,@"Settings fixture path");
    NSDictionary *result=@{@"paths":CheckPaths(),@"coalescing":CheckCoalescing(),@"settings":CheckSettings(@(argv[1]))};
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
    fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);return 0;
}}
