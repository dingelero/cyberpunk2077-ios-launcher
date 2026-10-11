#import <Foundation/Foundation.h>
#include <IOKit/IOReturn.h>

// iOS exposes a real IOKit registry for a limited set of services. Those
// symbols are re-exported directly. Desktop display and kext APIs have no
// equivalent app-owned service and must report that boundary honestly.
CFDictionaryRef IODisplayCreateInfoDictionary(uint32_t service, uint32_t options) {
    fprintf(stderr, "CP_IOKIT IODisplayCreateInfoDictionary service=%u unsupported\n", service);
    return NULL;
}
IOReturn IODisplayGetFloatParameter(uint32_t service, uint32_t options, CFStringRef parameter, float *value) {
    fprintf(stderr, "CP_IOKIT IODisplayGetFloatParameter service=%u unsupported\n", service);
    return kIOReturnUnsupported;
}
CFDictionaryRef KextManagerCopyLoadedKextInfo(CFArrayRef identifiers, CFArrayRef keys) {
    fprintf(stderr, "CP_IOKIT macOS kernel-extension registry unsupported\n");
    return NULL;
}
CFURLRef KextManagerCreateURLForBundleIdentifier(CFAllocatorRef allocator, CFStringRef identifier) { return NULL; }
