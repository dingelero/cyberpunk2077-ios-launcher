#import <Foundation/Foundation.h>
#import "GuestPaths.h"
#import "GameRoot.h"
#import "PathStrings.h"
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <fcntl.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <dirent.h>
#include <unistd.h>
#include <mach-o/dyld.h>
#include <stdatomic.h>

// The exported aliases intentionally have the desktop names. Looking them up
// in RTLD_DEFAULT or RTLD_NEXT could resolve the adapter again; the libSystem
// handle keeps our original function pointers independent of those aliases.
static void *CPSystemSymbol(const char *name) {
    static void *system; static dispatch_once_t once;
    dispatch_once(&once, ^{
        // -alias also affects this image's own undefined references. Bootstrap
        // the libSystem handle without calling our exported dlopen alias.
        void *(*loader)(const char *, int) = dlsym(RTLD_NEXT, "dlopen");
        if (loader) system = loader("/usr/lib/libSystem.B.dylib", RTLD_NOW | RTLD_LOCAL);
    });
    return system ? dlsym(system, name) : NULL;
}
static NSArray<NSString *> *CPRoots(void) { return @[CPGameRoot(), NSHomeDirectory()]; }
static NSString *CPDecodedPath(const char *path) {
    // NSString's fileSystemRepresentation raises for an empty string, while
    // POSIX reports its own error. Filesystem paths are byte strings, so an
    // undecodable UTF-8 input must also reach libc unchanged instead of being
    // reclassified as an adapter permission failure.
    if (!path || !path[0]) return nil;
    return CPGuestPathString(path);
}
static NSString *CPRetry(NSString *path, int failure) {
    if (!path.length || (failure != ENOENT && failure != ENOTDIR)) return nil;
    NSString *resolved = CPResolveGuestPath(path, CPRoots());
    if (resolved && ![resolved isEqualToString:path]) {
        fprintf(stderr, "CP_SYSTEM case_path %s -> %s\n", path.fileSystemRepresentation, resolved.fileSystemRepresentation);
        return resolved;
    }
    return nil;
}
static void CPPathFailure(const char *operation, NSString *source, NSString *mapped, int failure) {
    if (!getenv("CP2077_TRACE_PATH")) return;
    static atomic_uint count;
    if (atomic_fetch_add(&count, 1) < 256)
        fprintf(stderr, "CP_PATH %s_failed source=%s mapped=%s errno=%d\n", operation,
                source.UTF8String ?: "(undecodable)", mapped.UTF8String ?: "(denied)", failure);
}
#define CP_NATIVE(name, Type, failure) static Type native; static dispatch_once_t once; dispatch_once(&once, ^{ native = CPSystemSymbol(name); }); if (!native) { errno = ENOSYS; return failure; }

int CPGuestOpen(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list arguments; va_start(arguments, flags); mode = (mode_t)va_arg(arguments, int); va_end(arguments); }
    typedef int (*Fn)(const char *, int, ...); CP_NATIVE("open", Fn, -1)
    @autoreleasepool {
        NSString *decoded = CPDecodedPath(path);
        if (!decoded) return native(path, flags, mode);
        BOOL writing = (flags & (O_CREAT | O_TRUNC | O_WRONLY | O_RDWR)) != 0;
        NSString *mapped = CPMapGuestPath(decoded, writing);
        if (path && !mapped) { if(writing)CPPathFailure("open",decoded,nil,EACCES);errno = EACCES; return -1; }
        int value = native(mapped ? mapped.fileSystemRepresentation : path, flags, mode), saved = errno;
        if (value >= 0) return value;
        NSString *retry = CPRetry(mapped, saved);
        if (retry) { value=native(retry.fileSystemRepresentation,flags,mode);saved=errno; }
        if(value<0 && writing)CPPathFailure("open",decoded,retry ?: mapped,saved);
        errno = saved; return value;
    }
}
FILE *CPGuestFopen(const char *path, const char *mode) {
    typedef FILE *(*Fn)(const char *, const char *); CP_NATIVE("fopen", Fn, NULL)
    @autoreleasepool {
        NSString *decoded = CPDecodedPath(path);
        if (!decoded) return native(path, mode);
        BOOL writing = mode && (strchr(mode, 'w') || strchr(mode, 'a') || strchr(mode, '+'));
        NSString *mapped = CPMapGuestPath(decoded, writing);
        if (path && !mapped) { if(writing)CPPathFailure("fopen",decoded,nil,EACCES);errno = EACCES; return NULL; }
        FILE *value = native(mapped ? mapped.fileSystemRepresentation : path, mode); int saved = errno;
        if (value) return value;
        NSString *retry = CPRetry(mapped, saved);
        if (retry) { value=native(retry.fileSystemRepresentation,mode);saved=errno; }
        if(!value && writing)CPPathFailure("fopen",decoded,retry ?: mapped,saved);
        errno = saved; return value;
    }
}
FILE *CPGuestFreopen(const char *path, const char *mode, FILE *stream) {
    typedef FILE *(*Fn)(const char *, const char *, FILE *); CP_NATIVE("freopen", Fn, NULL)
    @autoreleasepool {
        NSString *decoded = CPDecodedPath(path);
        if (!decoded) return native(path, mode, stream);
        BOOL writing = mode && (strchr(mode, 'w') || strchr(mode, 'a') || strchr(mode, '+'));
        NSString *mapped = CPMapGuestPath(decoded, writing);
        if (path && !mapped) { errno = EACCES; return NULL; }
        // A failed freopen has already closed stream; it must never be retried.
        return native(mapped ? mapped.fileSystemRepresentation : path, mode, stream);
    }
}
#define CP_PATH_INT(Function, Original, ExtraType, ExtraName, Write) \
int Function(const char *path, ExtraType ExtraName) { \
    typedef int (*Fn)(const char *, ExtraType); CP_NATIVE(Original, Fn, -1) \
    @autoreleasepool { \
        NSString *decoded = CPDecodedPath(path); \
        if (!decoded) return native(path, ExtraName); \
        NSString *mapped = CPMapGuestPath(decoded, Write); \
        if (path && !mapped) { errno = EACCES; return -1; } \
        int result = native(mapped ? mapped.fileSystemRepresentation : path, ExtraName), saved = errno; \
        if (!result) return result; \
        NSString *retry = CPRetry(mapped, saved); \
        if (retry) return native(retry.fileSystemRepresentation, ExtraName); \
        errno = saved; return result; \
    } \
}
CP_PATH_INT(CPGuestStat, "stat", struct stat *, value, NO)
CP_PATH_INT(CPGuestAccess, "access", int, mode, (mode & W_OK) != 0)
#undef CP_PATH_INT
int CPGuestMkdir(const char *path, mode_t mode) {
    typedef int (*Fn)(const char *, mode_t); CP_NATIVE("mkdir", Fn, -1)
    @autoreleasepool {
        NSString *decoded=CPDecodedPath(path);
        if(!decoded)return native(path,mode);
        NSString *mapped=CPMapGuestPath(decoded,YES);
        if(!mapped){CPPathFailure("mkdir",decoded,nil,EACCES);errno=EACCES;return -1;}
        int result=native(mapped.fileSystemRepresentation,mode),saved=errno;
        if(result){NSString *retry=CPRetry(mapped,saved);
            if(retry){result=native(retry.fileSystemRepresentation,mode);saved=errno;mapped=retry;}
            if(result)CPPathFailure("mkdir",decoded,mapped,saved);
        }
        errno=saved;return result;
    }
}
#define CP_PATH_SINGLE(Function, Original, ResultType, Failure, Write) \
ResultType Function(const char *path) { \
    typedef ResultType (*Fn)(const char *); CP_NATIVE(Original, Fn, Failure) \
    @autoreleasepool { \
        NSString *decoded = CPDecodedPath(path); \
        if (!decoded) return native(path); \
        NSString *mapped = CPMapGuestPath(decoded, Write); \
        if (path && !mapped) { errno = EACCES; return Failure; } \
        ResultType value = native(mapped ? mapped.fileSystemRepresentation : path); int saved = errno; \
        if (value != Failure) return value; \
        NSString *retry = CPRetry(mapped, saved); \
        if (retry) return native(retry.fileSystemRepresentation); \
        errno = saved; return value; \
    } \
}
CP_PATH_SINGLE(CPGuestOpendir, "opendir", DIR *, NULL, NO)
CP_PATH_SINGLE(CPGuestChdir, "chdir", int, -1, NO)
CP_PATH_SINGLE(CPGuestUnlink, "unlink", int, -1, YES)
CP_PATH_SINGLE(CPGuestRmdir, "rmdir", int, -1, YES)
#undef CP_PATH_SINGLE

int CPGuestRename(const char *from, const char *to) {
    typedef int (*Fn)(const char *, const char *); CP_NATIVE("rename", Fn, -1)
    @autoreleasepool {
        NSString *decodedSource = CPDecodedPath(from), *decodedDestination = CPDecodedPath(to);
        if (!decodedSource || !decodedDestination) return native(from, to);
        NSString *source = CPMapGuestPath(decodedSource, YES);
        NSString *destination = CPMapGuestPath(decodedDestination, YES);
        if ((from && !source) || (to && !destination)) { errno = EACCES; return -1; }
        NSString *canonical = CPResolveGuestPath(source, CPRoots());
        return native(canonical ? canonical.fileSystemRepresentation : (source ? source.fileSystemRepresentation : from), destination ? destination.fileSystemRepresentation : to);
    }
}
void *CPGuestDlopen(const char *filename, int mode) {
    typedef void *(*Fn)(const char *, int); CP_NATIVE("dlopen", Fn, NULL)
    @autoreleasepool {
        NSString *path = CPDecodedPath(filename);
        if (!path) return native(filename, mode);
        NSString *frameworks = [CPHostBundle().bundlePath stringByAppendingPathComponent:@"Frameworks"];
        NSString *name = path.lastPathComponent;
        if ([name isEqualToString:@"AppKit"] || [name isEqualToString:@"Cocoa"] || [name isEqualToString:@"Carbon"]) name = @"libCPCompat.dylib";
        if ([name.pathExtension isEqualToString:@"dylib"]) {
            NSString *candidate = CPResolveGuestPath([frameworks stringByAppendingPathComponent:name], @[frameworks]);
            if (candidate && [NSFileManager.defaultManager fileExistsAtPath:candidate]) path = candidate;
        }
        void *value = native(path ? path.fileSystemRepresentation : filename, mode);
        if (filename) fprintf(stderr, "CP_SYSTEM dlopen source=%s resolved=%s result=%p%s\n", filename, path.fileSystemRepresentation ?: filename, value, value ? "" : " failed (dlerror preserved)");
        return value;
    }
}
int CPGuestGetExecutablePath(char *buffer, uint32_t *size) {
    if (!size) { errno = EINVAL; return -1; }
    @autoreleasepool {
        NSString *executable = [CPGameRoot() stringByAppendingPathComponent:@"Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077"];
        const char *path = executable.fileSystemRepresentation;
        size_t required = strlen(path) + 1;
        if (required > UINT32_MAX) { errno = ENAMETOOLONG; return -1; }
        if (!buffer || *size < required) { *size = (uint32_t)required; return -1; }
        memcpy(buffer, path, required); return 0;
    }
}
void *CPGuestMmap(void *address, size_t length, int protection, int flags, int descriptor, off_t offset) {
    typedef void *(*Fn)(void *, size_t, int, int, int, off_t); CP_NATIVE("mmap", Fn, MAP_FAILED)
    void *value = native(address, length, protection, flags, descriptor, offset); int saved = errno;
    if (value == MAP_FAILED) fprintf(stderr, "CP_VM mmap_failed hint=%p length=%llu prot=0x%x flags=0x%x fd=%d offset=%lld errno=%d\n", address, (unsigned long long)length, protection, flags, descriptor, (long long)offset, saved);
    else if (getenv("CP2077_TRACE_VM") && length >= 1024ULL * 1024 * 1024) fprintf(stderr, "CP_VM mmap hint=%p result=%p length=%llu prot=0x%x flags=0x%x fd=%d offset=%lld\n", address, value, (unsigned long long)length, protection, flags, descriptor, (long long)offset);
    errno = saved; return value;
}
#undef CP_NATIVE
