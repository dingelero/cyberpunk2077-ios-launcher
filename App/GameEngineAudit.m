#import "GameEngineAudit.h"
#include <mach/mach.h>
#include <string.h>

static uintptr_t CPParameterAddress;
static uintptr_t CPNodeAddress;
static NSString *CPAuditFailure = @"Guest image not audited yet";
static uint32_t CPReadWord(const uint8_t *bytes, size_t at) {
    uint32_t value;memcpy(&value,bytes+at,sizeof(value));return value;
}
static NSDictionary *CPAuditLocked(const struct mach_header_64 *header) {
    if(header) {
        CPParameterAddress=0;
        CPNodeAddress=0;
        BOOL uuid=NO,text=NO,data=NO;
        if(header->magic!=MH_MAGIC_64 || header->sizeofcmds>1024*1024)
            return @{@"accepted":@NO,@"reason":@"Invalid guest header"};
        const uint8_t *cursor=(const void *)(header+1),*end=cursor+header->sizeofcmds;
        for(uint32_t i=0;i<header->ncmds;i++) {
            if(cursor+sizeof(struct load_command)>end)break;
            const struct load_command *command=(const void *)cursor;
            if(command->cmdsize<sizeof(*command) || cursor+command->cmdsize>end)break;
            if(command->cmd==LC_UUID && command->cmdsize>=sizeof(struct uuid_command)) {
                const struct uuid_command *u=(const void *)command;
                uuid=[[[NSUUID alloc] initWithUUIDBytes:u->uuid].UUIDString isEqual:@"A6656ADC-FBE2-36A4-9B9D-B4A9DE645089"];
            }
            if(command->cmd==LC_SEGMENT_64 && command->cmdsize>=sizeof(struct segment_command_64)) {
                const struct segment_command_64 *s=(const void *)command;
                if(!strncmp(s->segname,"__TEXT",16) && s->vmaddr==0x100000000 && s->fileoff==0 && s->vmsize>0x21bc87c)
                    text=YES;
                if(!strncmp(s->segname,"__DATA",16) && s->vmaddr<=0x10900b654 &&
                   s->vmsize>=0x1090d39a0-s->vmaddr && s->vmaddr<=0x10900b724 && (s->initprot & VM_PROT_READ))
                    data=YES;
            }
            cursor+=command->cmdsize;
        }
        if(uuid && text && data) {
            uint32_t instructions[2]={0};vm_size_t copied=0;
            kern_return_t a=vm_read_overwrite(mach_task_self(),(uintptr_t)header+0x21bc7ec,4,(vm_address_t)&instructions[0],&copied);
            BOOL first=a==KERN_SUCCESS && copied==4 && instructions[0]==0x52800058;
            kern_return_t b=vm_read_overwrite(mach_task_self(),(uintptr_t)header+0x21bc878,4,(vm_address_t)&instructions[1],&copied);
            uint32_t display=0;vm_size_t displayCopied=0;
            kern_return_t c=vm_read_overwrite(mach_task_self(),(uintptr_t)header+0x1076200,4,(vm_address_t)&display,&displayCopied);
            if(first && b==KERN_SUCCESS && copied==4 && instructions[1]==0x52a00208 &&
               c==KERN_SUCCESS && displayCopied==4 && display==0x1e27d000) {
                CPParameterAddress=(uintptr_t)header+0x900b654;CPAuditFailure=nil;
                CPNodeAddress=(uintptr_t)header+0x90d394c;
            } else CPAuditFailure=@"Engine patch instructions do not match";
        } else CPAuditFailure=@"Guest UUID or parameter mapping does not match";
    }
    if(!CPParameterAddress)return @{@"accepted":@NO,@"reason":CPAuditFailure ?: @"Audit unavailable"};
    uint8_t bytes[0xd0]={0};vm_size_t copied=0;
    kern_return_t status=vm_read_overwrite(mach_task_self(),CPParameterAddress,sizeof(bytes),(vm_address_t)bytes,&copied);
    if(status!=KERN_SUCCESS || copied!=sizeof(bytes))return @{@"accepted":@NO,@"readStatus":@(status)};
    NSDictionary *current=@{@"TrickleMaxLoadingThreads":@(CPReadWord(bytes,0)),
        @"StreamMaxLoadingThreads":@(CPReadWord(bytes,0x40)),@"FloodMinNonLoadingThreads":@(CPReadWord(bytes,0x80)),
        @"DedicatedDecompressionMemoryBytes":@(CPReadWord(bytes,0xc0))};
    NSDictionary *defaults=@{@"StreamMaxLoadingThreads":@(CPReadWord(bytes,0x4c)),
        @"FloodMinNonLoadingThreads":@(CPReadWord(bytes,0x8c)),@"DedicatedDecompressionMemoryBytes":@(CPReadWord(bytes,0xcc))};
    BOOL defaultsMatch=[defaults[@"StreamMaxLoadingThreads"] isEqual:@2] && [defaults[@"FloodMinNonLoadingThreads"] isEqual:@2] && [defaults[@"DedicatedDecompressionMemoryBytes"] isEqual:@1048576];
    BOOL currentMatch=[current[@"StreamMaxLoadingThreads"] isEqual:@2] && [current[@"FloodMinNonLoadingThreads"] isEqual:@2] && [current[@"DedicatedDecompressionMemoryBytes"] isEqual:@1048576];
    uint8_t nodes[0x50]={0};vm_size_t nodeCopied=0;
    kern_return_t nodeStatus=vm_read_overwrite(mach_task_self(),CPNodeAddress,sizeof(nodes),(vm_address_t)nodes,&nodeCopied);
    BOOL nodesRead=nodeStatus==KERN_SUCCESS && nodeCopied==sizeof(nodes);
    NSDictionary *nodeReport=nodesRead?@{@"current":@(CPReadWord(nodes,0)),@"nativeDefault":@(CPReadWord(nodes,0xc)),
        @"whileLoadingCurrent":@(CPReadWord(nodes,0x40)),@"whileLoadingDefault":@(CPReadWord(nodes,0x4c))}:@{@"readStatus":@(nodeStatus)};
    BOOL nodeMatch=nodesRead && CPReadWord(nodes,0)==192 && CPReadWord(nodes,0xc)==300 &&
        CPReadWord(nodes,0x40)==999999 && CPReadWord(nodes,0x4c)==999999;
    return @{@"accepted":@YES,@"enginePatch":@"mobile-native30-v2",@"nativeCurrent":current,@"nativeDefaults":defaults,
        @"vSyncOffDisplayLinkRequestedFPS":@30,@"nativeDisplayCallbackRateObserved":@NO,
        @"nodeAttachmentBudget":nodeReport,@"nodeBudgetApplicationVerified":@(nodeMatch),
        @"patchedDefaultsVerified":@(defaultsMatch),@"configurationApplicationVerified":@(defaultsMatch && currentMatch && nodeMatch),
        @"scope":@"Read-only native parameter values; buffer use, gameplay correctness and frame-time improvement require user QA",
        @"stutterReductionVerified":@NO,@"sustained30FPSVerified":@NO};
}

NSDictionary *CPGameEnginePatchAudit(const struct mach_header_64 *header) {
    // Startup publishes addresses while utility-queue sampling may already be
    // active. Serialize both initialization and snapshots without UIKit calls.
    static NSObject *lock;static dispatch_once_t once;
    dispatch_once(&once,^{lock=[NSObject new];});
    @synchronized(lock) { return CPAuditLocked(header); }
}
