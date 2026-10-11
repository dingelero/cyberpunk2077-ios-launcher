#import <Foundation/Foundation.h>
#import "GameJSON.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if(argc!=3)return 2;
        NSError *error=nil;
        NSData *raw=[NSData dataWithContentsOfFile:@(argv[1]) options:0 error:&error];
        id object=raw?[NSJSONSerialization JSONObjectWithData:raw options:NSJSONReadingMutableContainers error:&error]:nil;
        NSData *result=object?CPGameJSONData(object,&error):nil;
        if(!result || ![result writeToFile:@(argv[2]) options:NSDataWritingAtomic error:&error]) {
            fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 1;
        }
        // Reproduce the previous failure with the same native API, so the
        // comparison checks a real regression instead of a hand-made fixture.
        NSData *previous=[NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
        if(!previous || ![previous writeToFile:[@(argv[2]) stringByAppendingString:@".previous"] options:NSDataWritingAtomic error:&error])return 1;
        NSDictionary *invalid=@{@"type":@"float",@"value":@YES};
        error=nil;
        if(CPGameJSONData(invalid,&error) || !error)return 1;
        puts("Native game JSON serialization completed; invalid float boolean rejected.");return 0;
    }
}
