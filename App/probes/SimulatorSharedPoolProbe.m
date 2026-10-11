#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "SimulatorSharedBufferPool.h"

static void Log(NSString *key, id value) { fprintf(stderr,"CP_POOL_PROBE %s=%s\n",key.UTF8String,[value description].UTF8String); }
int main(void) {
    @autoreleasepool {
        id<MTLDevice> device=MTLCreateSystemDefaultDevice();
        MTLHeapDescriptor *descriptor=[MTLHeapDescriptor new]; descriptor.size=4*1024*1024;
        descriptor.storageMode=MTLStorageModeShared; descriptor.hazardTrackingMode=MTLHazardTrackingModeUntracked;
        CPSimulatorSharedBufferPool *pool=[[CPSimulatorSharedBufferPool alloc] initWithDevice:device descriptor:descriptor logger:Log];
        if (!device || !pool) return 2;
        BOOL copied=NO, nativeResources=NO, budget=NO, unsupported=NO;
        NSUInteger allocated=0;
        @autoreleasepool {
            NSUInteger length=1024*1024;
            id<MTLBuffer> source=[pool newBufferWithLength:length options:MTLResourceStorageModeShared];
            id<MTLBuffer> destination=[pool newBufferWithLength:length options:MTLResourceStorageModeShared];
            if (!source || !destination || !source.contents || !destination.contents) return 3;
            nativeResources=source.device==device && destination.device==device && !source.heap && !destination.heap &&
                source.storageMode==MTLStorageModeShared && destination.storageMode==MTLStorageModeShared;
            for (NSUInteger i=0;i<length;i++) ((unsigned char *)source.contents)[i]=(unsigned char)(i*37+11);
            memset(destination.contents,0,length);
            id<MTLCommandQueue> queue=[device newCommandQueue]; id<MTLCommandBuffer> command=[queue commandBuffer];
            id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
            [blit copyFromBuffer:source sourceOffset:0 toBuffer:destination destinationOffset:0 size:length];
            [blit endEncoding]; [command commit]; [command waitUntilCompleted];
            copied=command.status==MTLCommandBufferStatusCompleted && !command.error && !memcmp(source.contents,destination.contents,length);
            allocated=pool.usedSize;
            budget=[pool newBufferWithLength:descriptor.size options:MTLResourceStorageModeShared]==nil;
            unsupported=[pool newBufferWithLength:256 options:MTLResourceStorageModePrivate]==nil &&
                [pool newBufferWithLength:256 options:MTLResourceStorageModeShared offset:0]==nil &&
                [pool newTextureWithDescriptor:[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:16 height:16 mipmapped:NO]]==nil &&
                [pool maxAvailableSizeWithAlignment:3]==0;
        }
        BOOL reclaimed=pool.usedSize==0;
        NSDictionary *report=@{ @"nativeGPUCopyVerified":@(copied), @"nativeSharedBuffersVerified":@(nativeResources),
            @"capacityLimitVerified":@(budget), @"allocationReleaseVerified":@(reclaimed), @"unsupportedOperationsRejected":@(unsupported),
            @"allocatedDuringTest":@(allocated), @"allocatedAfterRelease":@(pool.usedSize),
            @"nativeHeap":@NO, @"heapEquivalenceVerified":@NO, @"physicalDeviceTest":@NO, @"gameplayVerified":@NO };
        NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:nil];
        fwrite(data.bytes,1,data.length,stdout); fputc('\n',stdout);
        return copied && nativeResources && budget && reclaimed && unsupported ? 0 : 1;
    }
}
