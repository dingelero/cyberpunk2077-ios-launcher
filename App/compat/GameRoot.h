#import <Foundation/Foundation.h>
#include <objc/runtime.h>

// The compatibility image exports a guest-only NSBundle linker alias. Runtime
// class names remain distinct, so this lookup obtains the real host bundle
// without letting our own class-symbol reference bind to the guest facade.
static inline NSBundle *CPHostBundle(void) { return [(id)objc_getClass("NSBundle") mainBundle]; }

// Game resources stay in a separate directory. CPGAME_ROOT is useful for the
// simulator and for a separately transferred Documents/GameData directory.
static inline NSString *CPGameRootFromHostBundle(NSBundle *bundle) {
    const char *environment = getenv("CPGAME_ROOT");
    if (environment && environment[0]) return [[NSString stringWithUTF8String:environment] stringByStandardizingPath];
    NSString *relative = [bundle objectForInfoDictionaryKey:@"CPGameRelativeRoot"];
    if (relative.length) return [[bundle.bundlePath stringByAppendingPathComponent:relative] stringByStandardizingPath];
    NSString *configured = [bundle objectForInfoDictionaryKey:@"CPGameRoot"];
    if (configured.length) return configured.stringByStandardizingPath;
    return [[NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"GameData"] stringByStandardizingPath];
}
static inline NSString *CPGameRoot(void) {
    // The host sets CPGAME_ROOT before loading any guest image and never
    // changes it while the engine runs. Freeze that launch configuration,
    // avoiding path standardization and bundle queries on every stat/open.
    // Keep the cwd-based fallback live when used outside the normal host.
    static NSString *launchRoot;static dispatch_once_t once;
    const char *value=getenv("CPGAME_ROOT");
    if(value && value[0]) {
        dispatch_once(&once,^{launchRoot=[[NSString stringWithUTF8String:value] stringByStandardizingPath];});
        return launchRoot;
    }
    return CPGameRootFromHostBundle(CPHostBundle());
}
