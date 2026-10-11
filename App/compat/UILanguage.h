#pragma once
#import <Foundation/Foundation.h>
// One preference shared by the launcher and compatibility UI. Never changes
// the game's text/voice language or the user's saved touch layout.
static inline NSString *CPUILanguage(void) {
    return [[NSUserDefaults.standardUserDefaults stringForKey:@"CP2077UILanguage"] isEqual:@"en"] ? @"en" : @"zh";
}
static inline NSString *CPUIString(NSString *chinese, NSString *english) {
    return [CPUILanguage() isEqual:@"en"] ? english : chinese;
}
static inline void CPSetUILanguage(NSString *language) {
    [NSUserDefaults.standardUserDefaults setObject:([language isEqual:@"en"] ? @"en" : @"zh") forKey:@"CP2077UILanguage"];
}
