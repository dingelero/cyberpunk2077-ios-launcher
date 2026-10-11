#import <Foundation/Foundation.h>

#define CP_PERFORMANCE_VERSION @"universal-v5"
BOOL CPPreparePerformanceFiles(NSString *gameRoot, NSError **error);
NSUInteger CPPerformanceDRSMinimum(void);
NSUInteger CPPerformanceDRSMaximum(void);
NSDictionary *CPPerformanceDeviceProfile(void);
