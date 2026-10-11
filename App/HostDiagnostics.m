#import "HostDiagnostics.h"
#import "GameEngineAudit.h"
#import <mach/mach.h>
#import <os/proc.h>
#import <sys/utsname.h>
#import <mach/mach_time.h>

static NSMutableDictionary *CPReport;
static dispatch_queue_t CPReportQueue;
static NSString *CPReportPath;
static NSString *CPLogPath;
static dispatch_source_t CPMemoryTimer;
static dispatch_source_t CPReportTimer;
static BOOL CPReportDirty;
static const void *CPReportQueueKey = &CPReportQueueKey;
static uint64_t CPLastCPUTime,CPLastCPUWallTime;
static NSMutableDictionary<NSNumber *, NSNumber *> *CPThreadTimes;
static uint64_t CPLastThreadWall;

static NSDictionary *CPThreadCPUReport(void) {
    thread_act_array_t threads=NULL;mach_msg_type_number_t count=0;
    kern_return_t status=task_threads(mach_task_self(),&threads,&count);
    if(status!=KERN_SUCCESS)return @{@"status":@(status)};
    uint64_t wall=mach_absolute_time();mach_timebase_info_data_t timebase;mach_timebase_info(&timebase);
    double elapsed=CPLastThreadWall?(wall-CPLastThreadWall)*(double)timebase.numer/timebase.denom/1e9:0;
    NSMutableDictionary *current=[NSMutableDictionary new];NSMutableArray *rows=[NSMutableArray new];
    for(unsigned i=0;i<count;i++) {
        thread_basic_info_data_t basic={0};thread_identifier_info_data_t identity={0};
        mach_msg_type_number_t n=THREAD_BASIC_INFO_COUNT,idCount=THREAD_IDENTIFIER_INFO_COUNT;
        if(thread_info(threads[i],THREAD_BASIC_INFO,(thread_info_t)&basic,&n)==KERN_SUCCESS &&
           thread_info(threads[i],THREAD_IDENTIFIER_INFO,(thread_info_t)&identity,&idCount)==KERN_SUCCESS) {
            uint64_t total=(uint64_t)(basic.user_time.seconds+basic.system_time.seconds)*1000000+basic.user_time.microseconds+basic.system_time.microseconds;
            NSNumber *key=@(identity.thread_id),*previous=CPThreadTimes[key];current[key]=@(total);
            if(previous && elapsed>0 && total>=previous.unsignedLongLongValue) {
                thread_extended_info_data_t extended={0};n=THREAD_EXTENDED_INFO_COUNT;
                kern_return_t named=thread_info(threads[i],THREAD_EXTENDED_INFO,(thread_info_t)&extended,&n);
                NSString *name=named==KERN_SUCCESS?[[NSString alloc] initWithBytes:extended.pth_name length:strnlen(extended.pth_name,MAXTHREADNAMESIZE) encoding:NSUTF8StringEncoding]:nil;
                [rows addObject:@{@"threadID":key,@"name":name ?: @"",@"runState":@(basic.run_state),
                    @"cpuCoreEquivalentPercent":@(100.0*(total-previous.unsignedLongLongValue)/1e6/elapsed)}];
            }
        }
        mach_port_deallocate(mach_task_self(),threads[i]);
    }
    vm_deallocate(mach_task_self(),(vm_address_t)threads,count*sizeof(thread_t));
    CPThreadTimes=current;CPLastThreadWall=wall;
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"cpuCoreEquivalentPercent"] compare:a[@"cpuCoreEquivalentPercent"]];}];
    return @{@"status":@0,@"threadCount":@(count),@"intervalSeconds":@(elapsed),
        @"topThreads":[rows subarrayWithRange:NSMakeRange(0,MIN(8,rows.count))],
        @"scope":@"Native per-thread CPU time deltas; no thread suspension, debugger or call-stack inference"};
}

static void CPWriteReport(void) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:CPReport
                                                  options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                    error:&error];
    if (!data || ![data writeToFile:CPReportPath options:NSDataWritingAtomic error:&error])
        fprintf(stderr, "CP2077_RUNTIME report_write_error=%s\n", error.localizedDescription.UTF8String ?: "unknown");
    else CPReportDirty=NO;
}

static void CPPerformReport(void (^operation)(void)) {
    if (!CPReportQueue) return;
    if (dispatch_get_specific(CPReportQueueKey)) operation();
    else dispatch_sync(CPReportQueue, operation);
}

void CPHostRecordEvent(NSString *key, id value) {
    if (!key) return;
    if (!value) value = NSNull.null;
    if(!CPReportQueue)return;
    BOOL urgent=[key isEqual:@"launchFailure"] || [key isEqual:@"launchState"] || [key isEqual:@"uncaughtObjectiveCException"] || [key isEqual:@"guestEntryCalled"];
    NSTimeInterval producedAt=NSDate.date.timeIntervalSince1970;
    void (^record)(void)=^{
        id safe = [NSJSONSerialization isValidJSONObject:@[value]] ? value : [value description];
        CPReport[key] = safe;
        NSDictionary *event = @{ @"timestamp": @(producedAt), @"key": key, @"value": safe };
        NSMutableArray *events = CPReport[@"events"];
        [events addObject:event];
        if (events.count > 160) [events removeObjectAtIndex:0];
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:event options:NSJSONWritingSortedKeys error:nil];
        NSString *line = [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
        fprintf(stderr, "CP2077_RUNTIME %s\n", line.UTF8String ?: key.UTF8String);
        NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:CPLogPath];
        if (log) {
            @try {
                [log seekToEndOfFile];
                [log writeData:[[NSString stringWithFormat:@"CP2077_RUNTIME %@\n", line ?: key] dataUsingEncoding:NSUTF8StringEncoding]];
                [log closeFile];
            } @catch (__unused NSException *exception) { }
        }
        CPReport[@"updatedAt"] = @([NSDate date].timeIntervalSince1970);
        CPReportDirty=YES;if(urgent)CPWriteReport();
    };
    // Rendering/audio producers never wait for JSON serialization or storage.
    // Critical startup/failure reports still drain the queue synchronously.
    if(dispatch_get_specific(CPReportQueueKey))record();
    else if(urgent)dispatch_sync(CPReportQueue,record);
    else dispatch_async(CPReportQueue,record);
}

static void CPUnhandledException(NSException *exception) {
    CPHostRecordEvent(@"uncaughtObjectiveCException", @{ @"name": exception.name ?: @"", @"reason": exception.reason ?: @"", @"stack": exception.callStackSymbols ?: @[] });
    CPHostReportFailure(@"uncaught_objective_c_exception",exception.reason ?: exception.name);
}

void CPHostDiagnosticsInitialize(NSDictionary *initial) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_queue_attr_t attributes=dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0);
        CPReportQueue = dispatch_queue_create("local.cyberpunk.host.diagnostics", attributes);
        dispatch_queue_set_specific(CPReportQueue, CPReportQueueKey, (void *)CPReportQueueKey, NULL);
        NSString *documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        [NSFileManager.defaultManager createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:nil];
        CPReportPath = [documents stringByAppendingPathComponent:@"probe-report.json"];
        CPLogPath = [documents stringByAppendingPathComponent:@"runtime.log"];
        // A fresh report describes this PID only; the text log may retain previous launches.
        if (![NSFileManager.defaultManager fileExistsAtPath:CPLogPath])
            [NSFileManager.defaultManager createFileAtPath:CPLogPath contents:nil attributes:nil];
        struct utsname machine = {0}; uname(&machine);
        CPReport = [@{ @"schemaVersion": @1, @"pid": @(getpid()), @"deviceModel": @(machine.machine),
                       @"systemVersion": NSProcessInfo.processInfo.operatingSystemVersionString,
                       @"runtimeVerified": @NO, @"gameplayVerified": @NO, @"events": [NSMutableArray new],
                       @"startedAt": @([NSDate date].timeIntervalSince1970),
                       @"execution": @{ @"cpu": @"native ARM64", @"jit": @NO, @"cpuEmulation": @NO, @"streaming": @NO } } mutableCopy];
        [CPReport addEntriesFromDictionary:initial ?: @{}];
        NSSetUncaughtExceptionHandler(CPUnhandledException);
        CPWriteReport();
        CPReportTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,CPReportQueue);
        dispatch_source_set_timer(CPReportTimer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,100*NSEC_PER_MSEC);
        dispatch_source_set_event_handler(CPReportTimer,^{if(CPReportDirty)CPWriteReport();});dispatch_resume(CPReportTimer);
    });
}

void CPHostReportFailure(NSString *stage, NSString *message) {
    CPHostRecordEvent(@"launchFailure", @{ @"stage": stage ?: @"unknown", @"message": message ?: @"unknown error" });
    CPHostRecordEvent(@"launchState", @"failed");
}

NSDictionary *CPHostDiagnosticSnapshot(void) {
    __block NSDictionary *snapshot = @{};
    CPPerformReport(^{ snapshot = [CPReport copy]; });
    return snapshot;
}

void CPHostStartMemoryTrace(id<MTLDevice> device, CPNativeMetalReportGetter metalReport) {
    CPHostStartPerformanceTrace(device,metalReport,YES);
}
void CPHostStartPerformanceTrace(id<MTLDevice> device, CPNativeMetalReportGetter metalReport, BOOL detailed) {
    if (CPMemoryTimer) return;
    CPMemoryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, CPReportQueue);
    unsigned interval=detailed?2:5;
    dispatch_source_set_timer(CPMemoryTimer, DISPATCH_TIME_NOW, interval * NSEC_PER_SEC, 250 * NSEC_PER_MSEC);
    NSString *traceName=[NSString stringWithFormat:@"performance-%d.jsonl",getpid()];
    NSString *tracePath=[[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:traceName];
    [NSFileManager.defaultManager createFileAtPath:tracePath contents:nil attributes:nil];
    NSFileHandle *trace=[NSFileHandle fileHandleForWritingAtPath:tracePath];
    __block NSUInteger traceBytes=0;__block BOOL traceLimited=NO;
    // Keep at most six sessions. Never read or alter game saves/resources.
    NSString *documents=tracePath.stringByDeletingLastPathComponent;
    NSMutableArray *sessions=[NSMutableArray new];
    for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:documents error:nil])
        if([name hasPrefix:@"performance-"] && [name hasSuffix:@".jsonl"])[sessions addObject:[documents stringByAppendingPathComponent:name]];
    [sessions sortUsingComparator:^NSComparisonResult(NSString *a,NSString *b){
        NSDate *x=[NSFileManager.defaultManager attributesOfItemAtPath:a error:nil].fileModificationDate;
        NSDate *y=[NSFileManager.defaultManager attributesOfItemAtPath:b error:nil].fileModificationDate;return [y compare:x];}];
    for(NSUInteger i=6;i<sessions.count;i++)if(![sessions[i] isEqual:tracePath])[NSFileManager.defaultManager removeItemAtPath:sessions[i] error:nil];
    CPHostRecordEvent(@"localPerformanceTrace",@{@"file":traceName,@"intervalSeconds":@(interval),@"maximumBytes":@(10*1024*1024),
        @"debuggerAttached":@NO,@"sceneVerified":@NO,@"enabledOnlyForDiagnosticLaunch":@NO,@"perThreadCPUEnabled":@(detailed)});
    dispatch_source_set_event_handler(CPMemoryTimer, ^{
        @autoreleasepool {
        NSDictionary *metal=metalReport?metalReport():@{};
        // Preserve prior foreground rows and avoid measurements of an inactive
        // renderer being mistaken for gameplay. Reset CPU interval across pauses.
        if([metal[@"active"] isEqual:@NO]){CPLastCPUWallTime=0;return;}
        NSDictionary *engine=CPGameEnginePatchAudit(NULL);
        CPHostRecordEvent(@"gameEnginePatch",engine);
        task_vm_info_data_t info = {0}; mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
        kern_return_t status = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
        NSMutableDictionary *sample = [@{ @"timestamp": @([NSDate date].timeIntervalSince1970),
                                           @"physicalMemory": @(NSProcessInfo.processInfo.physicalMemory),
                                           @"thermalState": @(NSProcessInfo.processInfo.thermalState),
                                           @"lowPowerModeEnabled": @(NSProcessInfo.processInfo.lowPowerModeEnabled),
                                           @"availableProcessMemory": @(os_proc_available_memory()),
                                           @"metalAllocatedBytes": device ? @(device.currentAllocatedSize) : NSNull.null,
                                           @"metalRecommendedMaxWorkingSetBytes":device?@(device.recommendedMaxWorkingSetSize):NSNull.null,
                                           @"taskInfoStatus": @(status) } mutableCopy];
        if (status == KERN_SUCCESS) {
            sample[@"physFootprint"] = @(info.phys_footprint); sample[@"virtualBytes"] = @(info.virtual_size);
            sample[@"residentBytes"]=@(info.resident_size);sample[@"compressedBytes"]=@(info.compressed);
            sample[@"internalBytes"]=@(info.internal);sample[@"externalBytes"]=@(info.external);
        }
        sample[@"pid"]=@(getpid());sample[@"sessionStartedAt"]=CPReport[@"startedAt"];
        sample[@"elapsedSinceLaunchSeconds"]=@([sample[@"timestamp"] doubleValue]-[CPReport[@"startedAt"] doubleValue]);
        if(detailed)sample[@"threadCPU"]=CPThreadCPUReport();
        task_absolutetime_info_data_t cpu={0};mach_msg_type_number_t cpuCount=TASK_ABSOLUTETIME_INFO_COUNT;
        kern_return_t cpuStatus=task_info(mach_task_self(),TASK_ABSOLUTETIME_INFO,(task_info_t)&cpu,&cpuCount);
        sample[@"cpuTimeStatus"]=@(cpuStatus);
        if(cpuStatus==KERN_SUCCESS) {
            uint64_t total=cpu.total_user+cpu.total_system,wall=mach_absolute_time();
            if(CPLastCPUWallTime && wall>CPLastCPUWallTime && total>=CPLastCPUTime)
                sample[@"cpuCoreEquivalentPercent"]=@(100.0*(total-CPLastCPUTime)/(wall-CPLastCPUWallTime));
            CPLastCPUTime=total;CPLastCPUWallTime=wall;
            sample[@"cpuPercentScope"]=@"Process CPU time delta divided by monotonic wall time; 100 percent is one CPU core";
        }
        CPHostRecordEvent(@"latestMemorySample", sample);
        NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"memory-report.json"];
        [[NSJSONSerialization dataWithJSONObject:sample options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path atomically:YES];
        if(trace && !traceLimited) {
            NSDictionary *row=@{@"pid":@(getpid()),@"timestamp":sample[@"timestamp"],@"memory":sample,
                @"metal":metal,@"engine":engine,@"displayPolicy":CPReport[@"displayPolicy"] ?: @{},@"sceneVerified":@NO};
            NSMutableData *line=[[NSJSONSerialization dataWithJSONObject:row options:0 error:nil] mutableCopy];
            if(line) {
                [line appendBytes:"\n" length:1];
                if(traceBytes+line.length>10*1024*1024){traceLimited=YES;[trace closeFile];CPHostRecordEvent(@"localPerformanceTraceLimitReached",@YES);}
                else @try {[trace writeData:line];traceBytes+=line.length;} @catch(NSException *error) {
                    traceLimited=YES;CPHostRecordEvent(@"localPerformanceTraceWriteError",error.reason ?: error.name);
                }
            }
        }
        }
    });
    dispatch_resume(CPMemoryTimer);
}
