#import "PathStrings.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#define CP_PATH_SLOTS 4
#define CP_PATH_BYTES 512
typedef struct {
    char bytes[CP_PATH_SLOTS][CP_PATH_BYTES];
    CFStringRef decoded[CP_PATH_SLOTS];
    unsigned nextDecoded;
} CPPathStrings;
static pthread_key_t CPPathKey;
static BOOL CPPathKeyValid, CPPathDisabled;
static void CPDestroyPathStrings(void *pointer) {
    CPPathStrings *cache=pointer;
    for(unsigned i=0;i<CP_PATH_SLOTS;i++) {
        if(cache->decoded[i])CFRelease(cache->decoded[i]);
    }
    free(cache);
}
static CPPathStrings *CPThreadPathStrings(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        const char *disabled=getenv("CP_PATH_STRING_CACHE_DISABLE");
        CPPathDisabled=disabled && !strcmp(disabled,"1");
        CPPathKeyValid=pthread_key_create(&CPPathKey,CPDestroyPathStrings)==0;
    });
    if(!CPPathKeyValid || CPPathDisabled)return NULL;
    CPPathStrings *cache=pthread_getspecific(CPPathKey);
    if(!cache) {
        cache=calloc(1,sizeof(*cache));
        if(cache && pthread_setspecific(CPPathKey,cache)!=0){free(cache);cache=NULL;}
    }
    return cache;
}
NSString *CPGuestPathString(const char *bytes) {
    if(!bytes || !bytes[0])return nil;
    size_t length=strnlen(bytes,CP_PATH_BYTES);
    if(length>=CP_PATH_BYTES)return [NSString stringWithUTF8String:bytes];
    CPPathStrings *cache=CPThreadPathStrings();
    if(!cache)return [NSString stringWithUTF8String:bytes];
    for(unsigned i=0;i<CP_PATH_SLOTS;i++)
        if(cache->decoded[i] && !strcmp(cache->bytes[i],bytes))return (__bridge NSString *)cache->decoded[i];
    NSString *value=[NSString stringWithUTF8String:bytes];
    if(!value)return nil;
    unsigned slot=cache->nextDecoded++%CP_PATH_SLOTS;
    if(cache->decoded[slot])CFRelease(cache->decoded[slot]);
    memcpy(cache->bytes[slot],bytes,length+1);
    cache->decoded[slot]=(__bridge_retained CFStringRef)value;
    return value;
}
