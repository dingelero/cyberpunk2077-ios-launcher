#import <Foundation/Foundation.h>

// Memoize string conversion only. Existence, permissions, overlay precedence
// and the current directory are still queried live by GuestPaths/SystemBridge.
NSString *CPGuestPathString(const char *bytes);
