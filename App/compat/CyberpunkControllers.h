#import <Foundation/Foundation.h>
typedef void (*CPControllerLogger)(NSString *key, id value);
void CPInstallControllers(CPControllerLogger logger, BOOL trace);
void CPControllersGuestLoaded(void);
void CPControllersGuestStopped(void);
void CPControllersTouchReady(void);
NSDictionary *CPControllerRuntimeReport(void);
