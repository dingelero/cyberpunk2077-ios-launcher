#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
typedef void (*CPMetalLogger)(NSString *key, id value);
void CPInstallMetalLifecycle(CPMetalLogger logger);
void CPMetalSetApplicationActive(BOOL active);
BOOL CPMetalApplicationActive(void);
NSDictionary *CPMetalRuntimeReport(void);
