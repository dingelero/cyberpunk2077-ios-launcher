#import "SimulatorSharedBufferPool.h"
#import <objc/runtime.h>

#if TARGET_OS_SIMULATOR
@interface CPSimulatorSharedBufferPool ()
- (void)releaseBytes:(NSUInteger)bytes;
@end
@interface CPSimulatorBufferReservation : NSObject
@property (nonatomic, weak) CPSimulatorSharedBufferPool *pool;
@property (nonatomic) NSUInteger bytes;
@end
@implementation CPSimulatorBufferReservation
- (void)dealloc { [self.pool releaseBytes:self.bytes]; }
@end
static char CPBufferReservationKey;

@implementation CPSimulatorSharedBufferPool {
    id<MTLDevice> _device;
    NSUInteger _size, _used;
    MTLCPUCacheMode _cpuCacheMode;
    MTLHazardTrackingMode _hazardTrackingMode;
    CPMetalLogger _logger;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device descriptor:(MTLHeapDescriptor *)descriptor logger:(CPMetalLogger)logger {
    if (descriptor.storageMode != MTLStorageModeShared || descriptor.type != MTLHeapTypeAutomatic) return nil;
    if ((self=[super init])) {
        _device=device; _size=descriptor.size; _cpuCacheMode=descriptor.cpuCacheMode;
        _hazardTrackingMode=descriptor.hazardTrackingMode; _logger=logger;
        if (_logger) _logger(@"simulatorSharedPoolCreated", @{ @"budgetBytes": @(_size), @"nativeHeap": @NO,
            @"backend": @"native Metal Shared buffers", @"diagnosticOnly": @YES,
            @"supportsPlacementOrAliasing": @NO, @"supportsTexturesOrResidency": @NO });
    }
    return self;
}
- (id<MTLDevice>)device { return _device; }
- (MTLStorageMode)storageMode { return MTLStorageModeShared; }
- (MTLCPUCacheMode)cpuCacheMode { return _cpuCacheMode; }
- (MTLHazardTrackingMode)hazardTrackingMode { return _hazardTrackingMode; }
- (MTLResourceOptions)resourceOptions {
    return ((NSUInteger)_cpuCacheMode << MTLResourceCPUCacheModeShift) |
           ((NSUInteger)_hazardTrackingMode << MTLResourceHazardTrackingModeShift);
}
- (MTLHeapType)type { return MTLHeapTypeAutomatic; }
- (NSUInteger)size { return _size; }
- (NSUInteger)usedSize { @synchronized(self) { return _used; } }
- (NSUInteger)currentAllocatedSize { return self.usedSize; }
- (NSUInteger)allocatedSize { return self.usedSize; }
- (void)releaseBytes:(NSUInteger)bytes { @synchronized(self) { _used-=bytes; } }
- (NSUInteger)maxAvailableSizeWithAlignment:(NSUInteger)alignment {
    if (alignment && (alignment & (alignment-1))) return 0;
    @synchronized(self) { NSUInteger remaining=_size-_used; return alignment ? remaining & ~(alignment-1) : remaining; }
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options {
    if ((options & MTLResourceStorageModeMask) != MTLResourceStorageModeShared ||
        (options & MTLResourceCPUCacheModeMask) != ((NSUInteger)_cpuCacheMode << MTLResourceCPUCacheModeShift)) {
        if (_logger) _logger(@"simulatorSharedPoolRejected", @"Buffer storage/cache mode differs from pool");
        return nil;
    }
    @synchronized(self) {
        if (length > _size-_used) return nil;
        MTLResourceOptions nativeOptions=(options & ~MTLResourceHazardTrackingModeMask) |
            ((NSUInteger)_hazardTrackingMode << MTLResourceHazardTrackingModeShift);
        id<MTLBuffer> buffer=[_device newBufferWithLength:length options:nativeOptions];
        if (!buffer) return nil;
        // MTLSimBuffer reports allocatedSize == 0 on this runtime. Charge the
        // logical pool for page-rounded real buffer length as a lower bound;
        // keep the native reported number separate in the diagnostics.
        if (length > NSUIntegerMax-4095) return nil;
        NSUInteger allocated=MAX(buffer.allocatedSize,(length+4095)&~(NSUInteger)4095);
        if (allocated > _size-_used) return nil;
        _used+=allocated;
        CPSimulatorBufferReservation *reservation=[CPSimulatorBufferReservation new];
        reservation.pool=self; reservation.bytes=allocated;
        objc_setAssociatedObject(buffer,&CPBufferReservationKey,reservation,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (_logger) _logger(@"simulatorSharedPoolBuffer", @{ @"length": @(length), @"reservedPoolBytes": @(allocated),
            @"nativeReportedAllocatedBytes": @(buffer.allocatedSize),
            @"usedBytes": @(_used), @"nativeBuffer": @YES, @"nativeHeap": @(buffer.heap!=nil),
            @"storageMode": @(buffer.storageMode), @"cpuAccessible": @(buffer.contents!=NULL) });
        return buffer;
    }
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options offset:(NSUInteger)offset {
    if (_logger) _logger(@"simulatorSharedPoolRejected", @"Placement/aliasing unsupported by diagnostic buffer pool");
    return nil;
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor {
    if (_logger) _logger(@"simulatorSharedPoolRejected", @"Texture allocation unsupported by diagnostic buffer pool");
    return nil;
}
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor offset:(NSUInteger)offset {
    return [self newTextureWithDescriptor:descriptor];
}
@end
#endif
