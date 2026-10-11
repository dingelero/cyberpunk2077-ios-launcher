#import <Foundation/Foundation.h>
// CPGAME_ROOT is the Steam game directory (archive/, engine/, r6/, and the app).
static inline NSString *CPGameRootPath(void) {
    const char *value=getenv("CPGAME_ROOT");
    return value && *value ? [NSString stringWithUTF8String:value].stringByStandardizingPath : nil;
}
static inline NSString *CPGameBundlePath(void) {
    NSString *root=CPGameRootPath();
    if(!root)return nil;
    if([root.pathExtension isEqualToString:@"app"])return root;
    return [root stringByAppendingPathComponent:@"Cyberpunk2077.app"];
}
