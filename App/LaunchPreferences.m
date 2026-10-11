#import "LaunchPreferences.h"
#include <math.h>
static NSDictionary *Profile(NSString *identifier,NSString *title,NSString *english,NSUInteger minimum,NSUInteger maximum) {
    return @{@"id":identifier,@"title":title,@"title_en":english,@"DRSMinimum":@(minimum),@"DRSMaximum":@(maximum),@"outputHeight":@720};
}
NSArray<NSDictionary *> *CPDeviceProfiles(void) {
    static NSArray *profiles;static dispatch_once_t once;dispatch_once(&once,^{profiles=@[
        Profile(@"phone-a15-a16",@"iPhone 13 / 14 / 15 · A15 / A16",@"iPhone 13 / 14 / 15 · A15 / A16",50,50),
        Profile(@"phone-a17",@"iPhone 15 Pro / Pro Max · A17 Pro",@"iPhone 15 Pro / Pro Max · A17 Pro",40,50),
        Profile(@"phone-a18-plus",@"iPhone 16 及更新机型 · A18 及以上",@"iPhone 16 or newer · A18 and later",40,50),
        Profile(@"tablet-a-series",@"iPad / iPad mini · A 系列",@"iPad / iPad mini · A-series",50,50),
        Profile(@"tablet-m1-m2",@"iPad Air / Pro · M1 / M2",@"iPad Air / Pro · M1 / M2",40,60),
        Profile(@"tablet-m3-plus",@"iPad Air / Pro · M3 / M4 / M5 及以上",@"iPad Air / Pro · M3 / M4 / M5 or newer",40,67)
    ];});return profiles;
}
NSDictionary *CPDeviceProfile(NSString *identifier) {
    for(NSDictionary *profile in CPDeviceProfiles())if([profile[@"id"] isEqual:identifier])return profile;return nil;
}
NSString *CPAutomaticDeviceProfile(NSString *gpuName,BOOL tablet) {
    NSString *name=[[gpuName ?: @"" uppercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSRegularExpression *chip=[NSRegularExpression regularExpressionWithPattern:@"(?:APPLE)?([AM])([0-9]+)(?:PRO|MAX|ULTRA|GPU|$)" options:0 error:NULL];
    NSTextCheckingResult *match=[chip firstMatchInString:name options:0 range:NSMakeRange(0,name.length)];
    NSString *family=match?[name substringWithRange:[match rangeAtIndex:1]]:@"";
    NSInteger generation=match?[[name substringWithRange:[match rangeAtIndex:2]] integerValue]:0;
    if(tablet) {
        if([family isEqual:@"M"] && generation>=3)return @"tablet-m3-plus";
        if([family isEqual:@"M"] && generation>=1)return @"tablet-m1-m2";
        return @"tablet-a-series";
    }
    if([family isEqual:@"A"] && generation>=18)return @"phone-a18-plus";
    if([family isEqual:@"A"] && generation==17)return @"phone-a17";
    return @"phone-a15-a16"; // Unknown GPU: conservative, manually selectable.
}
NSMutableDictionary *CPValidatedLaunchPreferences(id source) {
    NSMutableDictionary *result=[@{@"schema":@1,@"profile":@"auto",@"outputHeight":@720} mutableCopy];
    if(![source isKindOfClass:NSDictionary.class] || ![source[@"schema"] isEqual:@1])return result;
    if([source[@"profile"] isKindOfClass:NSString.class] && ([source[@"profile"] isEqual:@"auto"] || CPDeviceProfile(source[@"profile"])))result[@"profile"]=source[@"profile"];
    if([source[@"outputHeight"] isKindOfClass:NSNumber.class] && ([source[@"outputHeight"] isEqual:@720] || [source[@"outputHeight"] isEqual:@1080]))result[@"outputHeight"]=source[@"outputHeight"];
    return result;
}
NSMutableDictionary *CPLoadLaunchPreferences(void) {return CPValidatedLaunchPreferences([NSUserDefaults.standardUserDefaults objectForKey:@"CP2077LaunchPreferences"]);}
void CPSaveLaunchPreferences(NSDictionary *preferences) {[NSUserDefaults.standardUserDefaults setObject:CPValidatedLaunchPreferences(preferences) forKey:@"CP2077LaunchPreferences"];}
NSDictionary *CPResolveLaunchProfile(NSDictionary *preferences,NSString *gpuName,BOOL tablet) {
    NSDictionary *checked=CPValidatedLaunchPreferences(preferences);NSString *identifier=checked[@"profile"];
    if([identifier isEqual:@"auto"])identifier=CPAutomaticDeviceProfile(gpuName,tablet);
    NSMutableDictionary *profile=[CPDeviceProfile(identifier) mutableCopy];profile[@"outputHeight"]=checked[@"outputHeight"];return profile;
}
CGSize CPOutputRenderSize(CGSize screen,NSUInteger height) {
    CGFloat wide=MAX(screen.width,screen.height),shortSide=MIN(screen.width,screen.height);
    if(!isfinite(wide) || !isfinite(shortSide) || shortSide<=0 || (height!=720 && height!=1080))return CGSizeZero;
    return CGSizeMake(2*round(wide/shortSide*height/2),height);
}
NSString *CPDisplayPolicyKey(NSString *version,NSDictionary *profile,CGSize size,NSUInteger minimum) {
    return [NSString stringWithFormat:@"%@/%@/%.0fx%.0f/%lu-%@",version,profile[@"id"],size.width,size.height,(unsigned long)minimum,profile[@"DRSMaximum"]];
}
