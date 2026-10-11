#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *CPResolveGuestPath(NSString *path, NSArray<NSString *> *roots);
FOUNDATION_EXPORT NSString *CPMapGuestPath(NSString *path, BOOL writing);
FOUNDATION_EXPORT BOOL CPPrepareGuestWritableDirectories(NSError **error);
