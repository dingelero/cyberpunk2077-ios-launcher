#import <Foundation/Foundation.h>

// The game's RapidJSON reader requires decimal tokens for float options,
// including integral-valued floats such as 100.0. Foundation alone emits 100.
NSData *CPGameJSONData(id object, NSError **error);
