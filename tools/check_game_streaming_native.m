#import <Foundation/Foundation.h>
#import "GameEngineAudit.h"
#include <sys/mman.h>
#include <string.h>

extern void cp_defaults_before(void *,void *,void *);
extern void cp_defaults_after(void *,void *,void *);
extern unsigned cp_native_limit(unsigned,unsigned);
static void require(BOOL success,NSString *message) {
    if(!success){fprintf(stderr,"%s\n",message.UTF8String);exit(1);}
}
static uint32_t word(const void *p,size_t offset) {uint32_t v;memcpy(&v,(const uint8_t *)p+offset,4);return v;}
static void put(void *p,size_t offset,uint32_t v) {memcpy((uint8_t *)p+offset,&v,4);}
int main(void) {@autoreleasepool {
    uint8_t before[3][64],after[3][64];memset(before,0xa5,sizeof(before));memcpy(after,before,sizeof(after));
    cp_defaults_before(before[0],before[1],before[2]);cp_defaults_after(after[0],after[1],after[2]);
    const uint32_t old[3]={2,2,1048576},new[3]={3,3,4194304};
    for(unsigned i=0;i<3;i++)for(unsigned at=0;at<64;at++) {
        if((at>=0x2c && at<0x30)||(at>=0x38 && at<0x3c))continue;
        require(before[i][at]==0xa5 && after[i][at]==0xa5,@"Unexpected object-field write");
    }
    for(unsigned i=0;i<3;i++) {
        require(word(before[i],0x2c)==old[i] && word(before[i],0x38)==old[i],@"Original native stores differ");
        require(word(after[i],0x2c)==new[i] && word(after[i],0x38)==new[i],@"Patched native stores differ");
    }
    unsigned limits=0;
    for(unsigned desired=0;desired<=16;desired++)for(unsigned workers=0;workers<=16;workers++) {
        require(cp_native_limit(desired,workers)==MIN(MAX(1,desired),workers+1),@"Native worker-limit clamp differs");limits++;
    }
    size_t size=0x900c000;uint8_t *image=mmap(NULL,size,PROT_READ|PROT_WRITE,MAP_ANON|MAP_PRIVATE,-1,0);
    require(image!=MAP_FAILED,@"Fixture mapping failed");
    struct mach_header_64 *h=(void *)image;h->magic=MH_MAGIC_64;h->ncmds=3;
    h->sizeofcmds=sizeof(struct uuid_command)+2*sizeof(struct segment_command_64);
    struct uuid_command *u=(void *)(h+1);u->cmd=LC_UUID;u->cmdsize=sizeof(*u);
    [[[NSUUID alloc] initWithUUIDString:@"A6656ADC-FBE2-36A4-9B9D-B4A9DE645089"] getUUIDBytes:u->uuid];
    struct segment_command_64 *t=(void *)(u+1);t->cmd=LC_SEGMENT_64;t->cmdsize=sizeof(*t);
    strcpy(t->segname,"__TEXT");t->vmaddr=0x100000000;t->vmsize=0x5000000;
    struct segment_command_64 *d=t+1;*d=*t;strcpy(d->segname,"__DATA");d->vmaddr=0x109000000;d->vmsize=0x10000;d->initprot=VM_PROT_READ;
    put(image,0x21bc7ec,0x52800078);put(image,0x21bc878,0x52a00808);
    put(image,0x900b654,1);put(image,0x900b694,3);put(image,0x900b6d4,3);put(image,0x900b714,4194304);
    put(image,0x900b6a0,3);put(image,0x900b6e0,3);put(image,0x900b720,4194304);
    NSDictionary *snapshot=CPGameEnginePatchAudit(h);require([snapshot[@"configurationApplicationVerified"] boolValue],@"Read-only audit did not read fixture values");
    put(image,0x900b694,2);NSDictionary *override=CPGameEnginePatchAudit(NULL);
    require([override[@"patchedDefaultsVerified"] boolValue] && ![override[@"configurationApplicationVerified"] boolValue],@"Current/default distinction lost");
    require(word(image,0x900b694)==2,@"Audit wrote into guest memory");
    put(image,0x21bc7ec,0x52800058);require(![CPGameEnginePatchAudit(h)[@"accepted"] boolValue],@"Unpatched guest accepted");
    put(image,0x21bc7ec,0x52800078);u->uuid[0]^=1;
    require(![CPGameEnginePatchAudit(h)[@"accepted"] boolValue],@"Wrong guest UUID accepted");
    munmap(image,size);
    NSDictionary *report=@{@"nativeOriginalDefaults":@[@2,@2,@1048576],@"nativePatchedDefaults":@[@3,@3,@4194304],
        @"unrelatedFieldsUntouched":@YES,@"actualNativeClampCases":@(limits),@"readOnlyParameterAuditFixturePassed":@YES,
        @"scope":@"Native ARM64 extracted instruction and synthetic image tests, not execution of the full game",@"gameplayVerified":@NO,@"sustained30FPSVerified":@NO};
    NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);
}return 0;}
