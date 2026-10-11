#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
NSArray<NSDictionary *> *CPDeviceProfiles(void);
NSDictionary *CPDeviceProfile(NSString *identifier);
NSString *CPAutomaticDeviceProfile(NSString *gpuName, BOOL tablet);
NSMutableDictionary *CPValidatedLaunchPreferences(id source);
NSMutableDictionary *CPLoadLaunchPreferences(void);
void CPSaveLaunchPreferences(NSDictionary *preferences);
NSDictionary *CPResolveLaunchProfile(NSDictionary *preferences, NSString *gpuName, BOOL tablet);
CGSize CPOutputRenderSize(CGSize screen, NSUInteger height);
NSString *CPDisplayPolicyKey(NSString *version, NSDictionary *profile, CGSize renderSize, NSUInteger drsMinimum);
