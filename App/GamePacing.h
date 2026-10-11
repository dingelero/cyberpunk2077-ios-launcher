#import <Foundation/Foundation.h>
BOOL CPApplyGamePacing(NSMutableDictionary *settings,NSString *resolution,NSMutableArray *changes,NSError **error);
BOOL CPApplyMobilePacing(NSMutableDictionary *settings,NSString *resolution,NSUInteger drsMinimum,NSMutableArray *changes,NSError **error);
BOOL CPApplyDevicePacing(NSMutableDictionary *settings,NSString *resolution,NSUInteger drsMinimum,NSUInteger drsMaximum,NSMutableArray *changes,NSError **error);
NSMutableDictionary *CPInitialMobileSettings(NSDictionary *schema,NSError **error);
