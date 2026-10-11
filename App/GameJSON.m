#import "GameJSON.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

static BOOL CPJSONError(NSError **error, NSString *message) {
    if(error)*error=[NSError errorWithDomain:@"CPGameJSON" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}

static BOOL CPAppendGameJSON(id value, NSMutableString *text, BOOL floating, NSError **error) {
    if([value isKindOfClass:NSDictionary.class]) {
        if(floating)return CPJSONError(error,@"Float option has an object value");
        NSDictionary *dictionary=value;
        for(id key in dictionary)if(![key isKindOfClass:NSString.class])
            return CPJSONError(error,@"JSON object key is not a string");
        BOOL floatOption=[dictionary[@"type"] isEqual:@"float"];
        [text appendString:@"{"];
        BOOL first=YES;
        for(NSString *key in [dictionary.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if(!first)[text appendString:@","];first=NO;
            if(!CPAppendGameJSON(key,text,NO,error))return NO;
            [text appendString:@":"];
            BOOL floatField=floatOption && [@[@"value",@"default_value",@"min_value",@"max_value",@"step_value"] containsObject:key];
            if(!CPAppendGameJSON(dictionary[key],text,floatField,error))return NO;
        }
        [text appendString:@"}"];return YES;
    }
    if([value isKindOfClass:NSArray.class]) {
        if(floating)return CPJSONError(error,@"Float option has an array value");
        [text appendString:@"["];BOOL first=YES;
        for(id item in value) {
            if(!first)[text appendString:@","];first=NO;
            if(!CPAppendGameJSON(item,text,NO,error))return NO;
        }
        [text appendString:@"]"];return YES;
    }
    if(floating) {
        if(![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID())
            return CPJSONError(error,@"Float option has a nonnumeric value");
        double number=[value doubleValue];
        if(!isfinite(number))return CPJSONError(error,@"Float option is not finite");
    }
    // Let Foundation handle string escaping, booleans, null and integer width.
    NSString *token;
    if([value isKindOfClass:NSDecimalNumber.class]) {
        // Foundation's JSON writer can convert parsed decimal numbers to
        // binary double (e.g. 0.0500000007 -> 0.050000000699999998). Retain
        // the exact decimal value for unrelated game setting metadata.
        if(!isfinite([value doubleValue]))return CPJSONError(error,@"Decimal option is not finite");
        token=[value stringValue];
    } else {
        NSData *data=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingFragmentsAllowed error:error];
        if(!data)return NO;
        token=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    if(!token)return CPJSONError(error,@"JSON fragment is not UTF-8");
    if(floating && [token rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@".eE"]].location==NSNotFound)
        token=[token stringByAppendingString:@".0"];
    [text appendString:token];return YES;
}

NSData *CPGameJSONData(id object, NSError **error) {
    NSMutableString *text=[NSMutableString new];
    if(!CPAppendGameJSON(object,text,NO,error))return nil;
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}
