// Adapted from Stray-iOS (c) 2026 xzk49, MIT. See AppKitThirdParty.LICENSE.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import "AppKitGamePaths.h"
static Class NativeBundle(void) { return objc_getClass("NSBundle"); }

// The two-level Mach-O import alias points guest NSBundle at CPGameBundle.
// Apple's native NSBundle class and the host's direct Foundation binds remain intact.
@interface CPGameBundle : NSObject
@property(nonatomic,copy) NSString *bundlePath;
@property(nonatomic,strong) NSDictionary *infoDictionary;
+ (id)mainBundle;
+ (id)bundleWithPath:(NSString *)path;
+ (id)bundleForClass:(Class)cls;
@end
@implementation CPGameBundle
+ (id)mainBundle {
    NSString *path=CPGameBundlePath();
    if(!path) { NSLog(@"CP_BUNDLE missing CPGAME_ROOT"); return nil; }
    return [self bundleWithPath:path];
}
+ (id)bundleWithPath:(NSString *)path {
    if(!path.length)return nil;
    NSString *plist=[path stringByAppendingPathComponent:@"Contents/Info.plist"];
    if(![NSFileManager.defaultManager fileExistsAtPath:plist])return [NativeBundle() bundleWithPath:path];
    NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:plist];
    if(!info)return nil;
    CPGameBundle *bundle=[self new];bundle.bundlePath=path.stringByStandardizingPath;
    bundle.infoDictionary=info;return bundle;
}
+ (id)bundleWithURL:(NSURL *)url { return url.isFileURL?[self bundleWithPath:url.path]:nil; }
+ (id)bundleForClass:(Class)cls {
    // AppKit game classes reside in converted dylibs, so Foundation cannot infer
    // their original macOS bundle. Host and Apple classes retain native lookup.
    const char *name=class_getImageName(cls);
    if(name && (strstr(name,"CyberpunkGuest") || strstr(name,"libCyberpunk")))return [self mainBundle];
    return [NativeBundle() bundleForClass:cls];
}
+ (id)bundleWithIdentifier:(NSString *)identifier {
    id guest=[self mainBundle];
    if([[guest bundleIdentifier] isEqualToString:identifier])return guest;
    return [NativeBundle() bundleWithIdentifier:identifier];
}
+ (NSArray *)allBundles { id game=[self mainBundle];return game?[[NativeBundle() allBundles] arrayByAddingObject:game]:[NativeBundle() allBundles]; }
+ (NSArray *)allFrameworks { return [NativeBundle() allFrameworks]; }
+ (NSArray *)preferredLocalizationsFromArray:(NSArray *)localizations { return [NativeBundle() preferredLocalizationsFromArray:localizations]; }
+ (NSArray *)preferredLocalizationsFromArray:(NSArray *)localizations forPreferences:(NSArray *)preferences { return [NativeBundle() preferredLocalizationsFromArray:localizations forPreferences:preferences]; }
- (NSString *)executablePath {
    NSString *name=self.infoDictionary[@"CFBundleExecutable"];
    return name.length?[[self.bundlePath stringByAppendingPathComponent:@"Contents/MacOS"] stringByAppendingPathComponent:name]:nil;
}
- (NSString *)resourcePath { return [self.bundlePath stringByAppendingPathComponent:@"Contents/Resources"]; }
- (NSURL *)bundleURL { return [NSURL fileURLWithPath:self.bundlePath isDirectory:YES]; }
- (NSURL *)executableURL { NSString *path=self.executablePath;return path?[NSURL fileURLWithPath:path]:nil; }
- (NSURL *)resourceURL { return [NSURL fileURLWithPath:self.resourcePath isDirectory:YES]; }
- (NSString *)bundleIdentifier { return self.infoDictionary[@"CFBundleIdentifier"]; }
- (id)objectForInfoDictionaryKey:(NSString *)key { return self.infoDictionary[key]; }
- (NSDictionary *)localizedInfoDictionary { return self.infoDictionary; }
- (NSArray *)localizations {
    NSArray *declared=self.infoDictionary[@"CFBundleLocalizations"];
    if(declared)return declared;
    NSMutableArray *found=[NSMutableArray new];
    for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.resourcePath error:NULL])
        if([name.pathExtension isEqualToString:@"lproj"])[found addObject:name.stringByDeletingPathExtension];
    return found;
}
- (NSArray *)preferredLocalizations { return [NativeBundle() preferredLocalizationsFromArray:self.localizations]; }
- (NSString *)developmentLocalization { return self.infoDictionary[@"CFBundleDevelopmentRegion"]; }
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)type { return [self pathForResource:name ofType:type inDirectory:nil]; }
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)type inDirectory:(NSString *)directory {
    return [self pathForResource:name ofType:type inDirectory:directory forLocalization:nil];
}
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)type inDirectory:(NSString *)directory forLocalization:(NSString *)locale {
    if(!name.length)return nil;
    NSString *file=type.length?[name stringByAppendingPathExtension:type]:name;
    NSString *base=self.resourcePath;
    if(locale.length)base=[base stringByAppendingPathComponent:[locale stringByAppendingPathExtension:@"lproj"]];
    if(directory.length)base=[base stringByAppendingPathComponent:directory];
    NSString *path=[base stringByAppendingPathComponent:file];
    return [NSFileManager.defaultManager fileExistsAtPath:path]?path:nil;
}
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)type { return [self URLForResource:name withExtension:type subdirectory:nil]; }
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)type subdirectory:(NSString *)directory {
    NSString *path=[self pathForResource:name ofType:type inDirectory:directory];return path?[NSURL fileURLWithPath:path]:nil;
}
- (NSArray *)pathsForResourcesOfType:(NSString *)type inDirectory:(NSString *)directory {
    NSString *base=directory.length?[self.resourcePath stringByAppendingPathComponent:directory]:self.resourcePath;
    NSMutableArray *paths=[NSMutableArray new];
    for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:base error:NULL])
        if(!type.length || [name.pathExtension isEqualToString:type])[paths addObject:[base stringByAppendingPathComponent:name]];
    return paths;
}
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table {
    id bundle=[NativeBundle() bundleWithPath:self.resourcePath];
    return bundle?[bundle localizedStringForKey:key value:value table:table]:(value.length?value:key);
}
- (BOOL)isLoaded {
    for(uint32_t i=0;i<_dyld_image_count();i++) {
        const char *name=_dyld_get_image_name(i);
        if(name && strstr(name,"CyberpunkGuest"))return YES;
    }
    return NO;
}
- (Class)principalClass { NSString *name=self.infoDictionary[@"NSPrincipalClass"];return name?NSClassFromString(name):Nil; }
- (id)forwardingTargetForSelector:(SEL)selector { return [NativeBundle() bundleWithPath:self.bundlePath]; }
@end
