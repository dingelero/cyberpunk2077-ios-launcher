#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <dlfcn.h>

// Enumerate the actual native device. The iPhone has no desktop GPU hot-plug API.
NSArray *MTLCopyAllDevices(void) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    return device ? @[device] : @[];
}
NSArray *MTLCopyAllDevicesWithObserver(id *observer, void (^handler)(id, NSString *)) {
    if (observer) *observer = nil;
    NSArray *devices = MTLCopyAllDevices();
    NSLog(@"CP2077_RUNTIME native_metal_devices count=%lu hotplug_unsupported", (unsigned long)devices.count);
    return devices;
}
void MTLRemoveDeviceObserver(id observer) { }
