#import "GuestPaths.h"
#import "GameRoot.h"
#include <errno.h>

static BOOL CPInside(NSString *path, NSString *root) {
    return [path hasPrefix:root] && (path.length==root.length || (path.length>root.length && [path characterAtIndex:root.length]=='/'));
}
static NSString *CPWritableRoot(void) {
    static NSString *root;static dispatch_once_t once;
    dispatch_once(&once,^{root=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/GuestWritable"];});
    return root;
}
static NSString *CPPerformanceRoot(void) {
    static NSString *root;static dispatch_once_t once;
    dispatch_once(&once,^{const char *value=getenv("CP2077_PERFORMANCE_PROFILE_ROOT");if(value && value[0])root=@(value);});
    return root;
}
BOOL CPPrepareGuestWritableDirectories(NSError **error) {
    // The macOS engine assumes Application Support already exists. A freshly
    // installed UIKit container does not have it. Create only its actual game
    // directories; failures still stop startup and are never reported as success.
    NSString *support=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/CD Projekt Red/Cyberpunk 2077"];
    NSString *logs=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Cyberpunk 2077"];
    for(NSString *path in @[support,[support stringByAppendingPathComponent:@"saves"],logs,CPWritableRoot()]) {
        if(![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error])return NO;
    }
    return YES;
}

NSString *CPMapGuestPath(NSString *path, BOOL writing) {
    if (!path.length) return nil;
    NSString *root = CPGameRoot();
    NSString *absolute = path.isAbsolutePath ? path : [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:path];
    absolute = absolute.stringByStandardizingPath;
    // The game's native user settings and saves use this macOS-relative suffix.
    // Preserve the suffix, replacing only the account/container prefix.
    NSString *support = @"/Library/Application Support/CD Projekt Red/Cyberpunk 2077";
    NSRange userData = [absolute rangeOfString:support];
    if (userData.location != NSNotFound && (NSMaxRange(userData)==absolute.length || [absolute characterAtIndex:NSMaxRange(userData)]=='/')) {
        return [NSHomeDirectory() stringByAppendingPathComponent:[absolute substringFromIndex:userData.location + 1]];
    }
    // GameServices embeds its macOS build account in this path. Map only
    // the game's own log directory, with a component boundary; arbitrary
    // external Library paths remain subject to the sandbox restriction.
    NSString *logSuffix=@"/Library/Logs/Cyberpunk 2077";
    NSRange gameLog=[absolute rangeOfString:logSuffix];
    if(gameLog.location!=NSNotFound && (NSMaxRange(gameLog)==absolute.length || [absolute characterAtIndex:NSMaxRange(gameLog)]=='/')) {
        return [NSHomeDirectory() stringByAppendingPathComponent:[absolute substringFromIndex:gameLog.location+1]];
    }
    if ([absolute hasPrefix:@"/tmp/"] || [absolute hasPrefix:@"/private/tmp/"]) {
        NSString *suffix = [absolute substringFromIndex:[absolute hasPrefix:@"/tmp/"] ? 5 : 13];
        return [NSTemporaryDirectory() stringByAppendingPathComponent:suffix];
    }
    NSRange app = [absolute rangeOfString:@"/Cyberpunk2077.app/"];
    if (app.location != NSNotFound && !CPInside(absolute, root)) {
        absolute = [root stringByAppendingPathComponent:[absolute substringFromIndex:app.location + 1]];
    }
    if (CPInside(absolute, root)) {
        NSString *suffix = [absolute substringFromIndex:MIN(absolute.length, root.length + 1)];
        NSString *overlay = [CPWritableRoot() stringByAppendingPathComponent:suffix];
        if (writing) {
            [NSFileManager.defaultManager createDirectoryAtPath:CPWritableRoot() withIntermediateDirectories:YES attributes:nil error:NULL];
            // Mirror only parents that already exist in the read-only game
            // tree. Otherwise an original r6/ parent passes stat, while mkdir
            // of its writable child fails because the overlay lacks r6/.
            // Missing original parents remain missing: POSIX mkdir is not
            // silently changed into recursive directory creation.
            NSString *sourceParent=root, *overlayParent=CPWritableRoot();
            NSArray *parts=suffix.pathComponents;
            for(NSUInteger i=0;i+1<parts.count;i++) {
                sourceParent=[sourceParent stringByAppendingPathComponent:parts[i]];
                overlayParent=[overlayParent stringByAppendingPathComponent:parts[i]];
                BOOL directory=NO;
                if(![NSFileManager.defaultManager fileExistsAtPath:sourceParent isDirectory:&directory] || !directory)break;
                [NSFileManager.defaultManager createDirectoryAtPath:overlayParent withIntermediateDirectories:NO attributes:nil error:NULL];
            }
            return overlay;
        }
        if ([NSFileManager.defaultManager fileExistsAtPath:overlay]) return overlay;
        NSString *profile=CPPerformanceRoot(),*file=nil;
        if([suffix isEqual:@"engine/config/platform/mac/rendering.ini"])file=@"rendering.ini";
        if([suffix isEqual:@"r6/config/settings/platform/mac/options.json"])file=@"options.json";
        if(profile && file)return [profile stringByAppendingPathComponent:file];
        return absolute;
    }
    // Do not allow a simulator run to change arbitrary host files. The real
    // device's sandbox still performs its own permission and symlink checks.
    if (writing && !CPInside(absolute, NSHomeDirectory()) && !CPInside(absolute, NSTemporaryDirectory().stringByStandardizingPath)) {
        errno = EACCES;
        return nil;
    }
    return absolute;
}

NSString *CPResolveGuestPath(NSString *path, NSArray<NSString *> *roots) {
    if (!path.length) return nil;
    if (!path.isAbsolutePath) path = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:path];
    path = path.stringByStandardizingPath;
    NSArray<NSString *> *parts = path.pathComponents;
    for (NSString *root in roots) {
        NSArray<NSString *> *prefix = root.stringByStandardizingPath.pathComponents;
        if (parts.count < prefix.count) continue;
        BOOL inside = YES;
        for (NSUInteger i = 0; i < prefix.count; i++) {
            if ([parts[i] caseInsensitiveCompare:prefix[i]] != NSOrderedSame) { inside = NO; break; }
        }
        if (!inside) continue;
        NSString *resolved = root.stringByStandardizingPath;
        for (NSUInteger i = prefix.count; i < parts.count; i++) {
            NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:resolved error:NULL];
            if (!entries) return nil;
            NSString *part = parts[i];
            if ([entries containsObject:part]) { resolved = [resolved stringByAppendingPathComponent:part]; continue; }
            NSString *match = nil;
            for (NSString *entry in entries) {
                if ([entry caseInsensitiveCompare:part] == NSOrderedSame) {
                    if (match) return nil; // Ambiguous case is not a valid alias.
                    match = entry;
                }
            }
            if (!match) return i + 1 == parts.count ? [resolved stringByAppendingPathComponent:part] : nil;
            resolved = [resolved stringByAppendingPathComponent:match];
        }
        return resolved;
    }
    return nil;
}
