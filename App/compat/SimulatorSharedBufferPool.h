#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <TargetConditionals.h>
#import "MetalLifecycle.h"

#if TARGET_OS_SIMULATOR
// A diagnostic allocator of real native Shared buffers, not a native MTLHeap.
// It supports automatic buffer allocation only. Placement, aliasing, texture,
// acceleration-structure, residency-set and encoder useHeap semantics are not
// supplied. Do not enable it in a device build or claim native heap equivalence.
@interface CPSimulatorSharedBufferPool : NSObject
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLHeapDescriptor *)descriptor logger:(CPMetalLogger)logger;
@property (atomic, copy) NSString *label;
@property (nonatomic, readonly) id<MTLDevice> device;
@property (nonatomic, readonly) MTLStorageMode storageMode;
@property (nonatomic, readonly) MTLCPUCacheMode cpuCacheMode;
@property (nonatomic, readonly) MTLHazardTrackingMode hazardTrackingMode;
@property (nonatomic, readonly) MTLResourceOptions resourceOptions;
@property (nonatomic, readonly) MTLHeapType type;
@property (nonatomic, readonly) NSUInteger size, usedSize, currentAllocatedSize, allocatedSize;
- (NSUInteger)maxAvailableSizeWithAlignment:(NSUInteger)alignment;
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options;
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options offset:(NSUInteger)offset;
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor;
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor offset:(NSUInteger)offset;
@end
#endif
