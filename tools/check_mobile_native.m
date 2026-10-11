#import <Foundation/Foundation.h>
#import "GameEngineAudit.h"
#import "GamePacing.h"
#import "GameJSON.h"
#include "TouchMath.h"
#include <sys/mman.h>
#include <string.h>
typedef struct {float minimum,maximum,preferred;} CPRange;
extern CPRange cp_mobile_before(unsigned refresh);
extern CPRange cp_mobile_after(unsigned refresh);
static void require(BOOL success,NSString *message){if(!success){fprintf(stderr,"FAIL %s\n",message.UTF8String);exit(1);}}
static void put(void *p,size_t at,uint32_t value){memcpy((uint8_t *)p+at,&value,4);}
static BOOL numericEquivalent(id a,id b,BOOL floatField) {
    // The game reads explicitly typed "float" fields with RapidJSON GetFloat.
    // Compare their actual IEEE-754 float32 bits, not Foundation's unequal
    // decimal/binary NSNumber representations of the same game value.
    if(floatField && [a isKindOfClass:NSNumber.class] && [b isKindOfClass:NSNumber.class]) {
        float x=[a floatValue],y=[b floatValue];return memcmp(&x,&y,sizeof(float))==0;
    }
    if([a isKindOfClass:NSDictionary.class] && [b isKindOfClass:NSDictionary.class]) {
        if([a count]!=[b count])return NO;for(id key in a) {
            BOOL field=[a[@"type"] isEqual:@"float"] && [@[@"value",@"default_value",@"min_value",@"max_value",@"step_value"] containsObject:key];
            if(!numericEquivalent(a[key],b[key],field))return NO;
        }return YES;
    }
    if([a isKindOfClass:NSArray.class] && [b isKindOfClass:NSArray.class]) {
        if([a count]!=[b count])return NO;for(NSUInteger i=0;i<[a count];i++)if(!numericEquivalent(a[i],b[i],NO))return NO;return YES;
    }return [a isEqual:b];
}
static NSDictionary *settings(NSString *path) {
    NSData *raw=[NSData dataWithContentsOfFile:path];NSError *error=nil;
    NSMutableDictionary *value=[NSJSONSerialization JSONObjectWithData:raw options:NSJSONReadingMutableContainers error:&error];
    // Exercise the dynamic Off entry with a stale index; the game also stores
    // the selection index, so changing only its string is insufficient.
    for(NSMutableDictionary *g in value[@"data"])for(NSMutableDictionary *o in g[@"options"])
        if([o[@"name"] isEqual:@"VSync"])o[@"index"]=@2;
    raw=CPGameJSONData(value,&error);
    value=[NSJSONSerialization JSONObjectWithData:raw options:NSJSONReadingMutableContainers error:&error];
    NSDictionary *before=[NSJSONSerialization JSONObjectWithData:raw options:0 error:&error];
    NSMutableArray *changes=[NSMutableArray new];
    require(CPApplyMobilePacing(value,@"1564x720",40,changes,&error),error.localizedDescription ?: @"Settings migration");
    NSSet *allowed=[NSSet setWithArray:@[@"Resolution",@"MaximumFPS_OnOff",@"MaximumFPS_Value",@"DRS_TargetFPS",@"FrameGeneration",@"FSR3_FrameGeneration",@"ResolutionScaling",@"DynamicResolutionScaling",@"DRS_MinResolution",@"DRS_MaxResolution",@"FSR2",@"VSync",@"HDDMode"]];
    NSUInteger preserved=0;BOOL fg=NO,metal=NO;
    require([before[@"data"] count]==[value[@"data"] count],@"No groups removed");
    for(NSUInteger g=0;g<[before[@"data"] count];g++) {
        NSArray *left=before[@"data"][g][@"options"],*right=value[@"data"][g][@"options"];
        require(left.count==right.count,@"No options removed");
        for(NSUInteger i=0;i<left.count;i++) {
            if(![allowed containsObject:left[i][@"name"]]){require([left[i] isEqual:right[i]],@"Other options changed");preserved++;}
            if([right[i][@"name"] isEqual:@"FrameGeneration"])fg=[right[i][@"value"] isEqual:@"Off"] && [right[i][@"values"] containsObject:@"FSR3"];
            if([right[i][@"name"] isEqual:@"ResolutionScaling"])metal=[right[i][@"value"] isEqual:@"FSR2"] && [right[i][@"index"] isEqual:@1];
        }
    }
    require(fg && metal,@"Native MetalFX/FG default and available option preserved");
    for(NSDictionary *g in value[@"data"])for(NSDictionary *o in g[@"options"]) {
        if([o[@"name"] isEqual:@"MaximumFPS_OnOff"])require([o[@"value"] isEqual:@NO],@"Independent frame limiter still enabled");
        if([o[@"name"] isEqual:@"HDDMode"])require([o[@"value"] isEqual:@"Off"] && [o[@"index"] isEqual:@0],@"SSD selection not applied");
        if([o[@"name"] isEqual:@"VSync"])require([o[@"value"] isEqual:@"UI-Settings-Video-QualitySetting-Off"] && [o[@"index"] isEqual:@0],@"Display-loop setting inconsistent");
    }
    NSData *encoded=CPGameJSONData(value,&error);require(encoded!=nil,@"Typed serialization");
    NSDictionary *roundtrip=[NSJSONSerialization JSONObjectWithData:encoded options:0 error:nil];
    require(numericEquivalent(value,roundtrip,NO),@"JSON game float32 values or content changed during roundtrip");
    require(!CPApplyMobilePacing([@{@"data":@[]} mutableCopy],@"1564x720",40,[NSMutableArray new],&error),@"Empty settings were accepted");
    NSMutableArray *again=[NSMutableArray new];require(CPApplyMobilePacing(value,@"1564x720",40,again,&error) && !again.count,@"Migration is not idempotent");
    return @{@"otherOptionsPreserved":@(preserved),@"nativeMetalFXMachineEnumVerified":@YES,@"frameGenerationOptionRetained":@YES,@"changes":changes,@"idempotent":@YES};
}
int main(int argc,const char *argv[]) {@autoreleasepool {
    require(argc==2,@"Settings path required");
    for(unsigned refresh=1;refresh<=240;refresh++) {
        CPRange old=cp_mobile_before(refresh),new=cp_mobile_after(refresh);
        require(old.minimum==refresh && old.maximum==refresh && old.preferred==refresh,@"Original ARM instructions differ");
        require(new.minimum==30 && new.maximum==30 && new.preferred==30,@"Patched ARM instructions differ");
    }
    unsigned touchCases=0;
    for(int x=-100;x<=100;x++)for(int y=-100;y<=100;y++) {
        CPTouchAxis a=CPTouchNormalize(x,y,40);require(isfinite(a.x) && isfinite(a.y) && hypot(a.x,a.y)<=1.000001,@"Stick clamp invalid");touchCases++;
    }
    require(CPTouchNormalize(0,0,40).x==0 && CPTouchNormalize(4,0,40).x==0,@"Stick dead zone invalid");
    require(CPTouchNormalize(0,-40,40).y==1,@"Stick vertical sign invalid");
    require(!CPTouchShouldHide(13.999,10,0) && CPTouchShouldHide(14,10,0) && !CPTouchShouldHide(40,10,1),@"Hide boundary or held touch invalid");
    size_t size=0x90d4000;uint8_t *image=mmap(NULL,size,PROT_READ|PROT_WRITE,MAP_ANON|MAP_PRIVATE,-1,0);
    require(image!=MAP_FAILED,@"Fixture mapping failed");
    struct mach_header_64 *h=(void *)image;h->magic=MH_MAGIC_64;h->ncmds=3;
    h->sizeofcmds=sizeof(struct uuid_command)+2*sizeof(struct segment_command_64);
    struct uuid_command *u=(void *)(h+1);u->cmd=LC_UUID;u->cmdsize=sizeof(*u);
    [[[NSUUID alloc] initWithUUIDString:@"A6656ADC-FBE2-36A4-9B9D-B4A9DE645089"] getUUIDBytes:u->uuid];
    struct segment_command_64 *t=(void *)(u+1);t->cmd=LC_SEGMENT_64;t->cmdsize=sizeof(*t);strcpy(t->segname,"__TEXT");t->vmaddr=0x100000000;t->vmsize=0x5000000;
    struct segment_command_64 *d=t+1;*d=*t;strcpy(d->segname,"__DATA");d->vmaddr=0x109000000;d->vmsize=0xd4000;d->initprot=VM_PROT_READ;
    put(image,0x21bc7ec,0x52800058);put(image,0x21bc878,0x52a00208);put(image,0x1076200,0x1e27d000);
    put(image,0x900b654,1);put(image,0x900b694,2);put(image,0x900b6d4,2);put(image,0x900b714,1048576);
    put(image,0x900b6a0,2);put(image,0x900b6e0,2);put(image,0x900b720,1048576);
    put(image,0x90d394c,192);put(image,0x90d3958,300);put(image,0x90d398c,999999);put(image,0x90d3998,999999);
    require([CPGameEnginePatchAudit(h)[@"configurationApplicationVerified"] boolValue],@"Restored native parameter audit failed");
    put(image,0x90d394c,300);
    require(![CPGameEnginePatchAudit(NULL)[@"nodeBudgetApplicationVerified"] boolValue],@"Unapplied node configuration incorrectly marked verified");
    put(image,0x90d394c,192);
    put(image,0x900b694,3);NSDictionary *override=CPGameEnginePatchAudit(NULL);
    require([override[@"patchedDefaultsVerified"] boolValue] && ![override[@"configurationApplicationVerified"] boolValue],@"INI override distinction lost");
    put(image,0x1076200,0x1e220000);require(![CPGameEnginePatchAudit(h)[@"accepted"] boolValue],@"Unpatched display loop accepted");
    put(image,0x1076200,0x1e27d000);u->uuid[0]^=1;require(![CPGameEnginePatchAudit(h)[@"accepted"] boolValue],@"Wrong UUID accepted");munmap(image,size);
    NSDictionary *report=@{@"passed":@YES,@"actualARMDisplayRangeCases":@240,@"touchRadialClampCases":@(touchCases),@"hideAfterFourSecondsBoundaryPassed":@YES,
        @"nativeReadOnlyAuditFixturePassed":@YES,@"settings":settings(@(argv[1])),@"sustained30FPSFor30MinutesVerified":@NO,
        @"scope":@"Native ARM instructions and host component tests; not full game or physical iPhone performance"};
    NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);return 0;
}}
