#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
NSArray<NSDictionary *> *CPTouchButtons(void);
NSArray<NSDictionary *> *CPTouchBindings(void);
NSDictionary *CPTouchBinding(NSString *identifier);
NSMutableDictionary *CPTouchDefaultLayout(void);
NSMutableDictionary *CPTouchValidatedLayout(id source);
CGRect CPTouchButtonFrame(NSDictionary *definition,NSDictionary *setting,CGRect safeArea);
NSString *CPTouchLayoutPath(void);
