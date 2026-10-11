#import <Foundation/Foundation.h>
#import "TouchLayout.h"
#include "TouchInput.h"
#include <assert.h>
int main(int argc,char **argv){@autoreleasepool {
    CPTouchRouter router={0};CPTouchContact *move=CPTouchBegin(&router,1,CPTouchMove,-1,120,230);
    CPTouchContact *look=CPTouchBegin(&router,2,CPTouchLook,-1,610,180);
    assert(CPTouchBegin(&router,3,CPTouchButton,0,50,70));assert(CPTouchBegin(&router,4,CPTouchButton,1,860,70));
    CPTouchAxis a=CPTouchMovement(move,150,210,46);assert(a.x>0 && a.y>0);
    CPTouchDelta d=CPTouchRelativeLook(look,640,200,1.6,0);assert(fabs(d.x-48)<1e-8 && fabs(d.y-32)<1e-8);
    assert(router.move==1 && router.look==2 && CPTouchFind(&router,3)->control==0 && CPTouchFind(&router,4)->control==1);
    for(unsigned i=0;i<600;i++){d=CPTouchRelativeLook(look,640,200,1.6,0);assert(d.x==0 && d.y==0);}
    assert(CPTouchBegin(&router,5,CPTouchMove,-1,220,250)->role==CPTouchIgnored);
    assert(CPTouchBegin(&router,6,CPTouchLook,-1,680,220)->role==CPTouchIgnored);
    assert(CPTouchFind(&router,1)->role==CPTouchMove);a=CPTouchMovement(move,800,210,46);assert(a.x>0.99);
    CPTouchEnd(&router,1);assert(router.move==0 && router.look==2 && CPTouchFind(&router,3));
    CPTouchEnd(&router,2);assert(router.look==0);CPTouchEnd(&router,3);CPTouchEnd(&router,4);
    for(uintptr_t i=7;i<15;i++)CPTouchBegin(&router,i,CPTouchButton,0,0,0);
    assert(CPTouchBegin(&router,15,CPTouchButton,0,0,0)==NULL);assert(CPTouchBegin(&router,0,CPTouchMove,-1,0,0)==NULL);
    unsigned splitCases=0;
    for(unsigned count=1;count<=240;count++){
        CPTouchContact c={0};double x=0,y=0;
        for(unsigned i=1;i<=count;i++){d=CPTouchRelativeLook(&c,160.0*i/count,-90.0*i/count,2.1,0);x+=d.x;y+=d.y;}
        assert(fabs(x-336)<1e-8 && fabs(y+189)<1e-8);splitCases++;
    }
    CPTouchContact c={0};d=CPTouchRelativeLook(&c,10,10,2,1);assert(d.x==20 && d.y==-20);
    NSMutableDictionary *layout=CPTouchDefaultLayout();NSArray *definitions=CPTouchButtons();NSMutableSet *native=[NSMutableSet new];
    for(NSDictionary *b in definitions)if(CPTouchBinding(b[@"binding"]) && [CPTouchBinding(b[@"binding"])[@"key"] intValue]<0)[native addObject:b[@"binding"]];
    assert(native.count==16 && definitions.count==21);
    for(NSDictionary *binding in CPTouchBindings())assert([binding[@"title_en"] length]>0 && [binding[@"title"] length]>0);
    unsigned layouts=0;NSArray *areas=@[[NSValue valueWithRect:NSMakeRect(62,0,832,419)],[NSValue valueWithRect:NSMakeRect(47,0,750,369)],[NSValue valueWithRect:NSMakeRect(47,0,718,354)],[NSValue valueWithRect:NSMakeRect(50,0,924,748)],[NSValue valueWithRect:NSMakeRect(20,0,1094,810)],[NSValue valueWithRect:NSMakeRect(20,0,1326,986)],[NSValue valueWithRect:NSMakeRect(20,0,1094,790)],[NSValue valueWithRect:NSMakeRect(20,0,1080,724)]];
    for(NSValue *value in areas){NSRect n=value.rectValue;CGRect area=CGRectMake(n.origin.x,n.origin.y,n.size.width,n.size.height);NSMutableArray *frames=[NSMutableArray new];
        for(NSDictionary *b in definitions){CGRect frame=CPTouchButtonFrame(b,layout[@"buttons"][b[@"id"]],area);assert(CGRectContainsRect(area,frame));
            for(NSValue *old in frames){NSRect r=old.rectValue;CGRect previous=CGRectMake(r.origin.x,r.origin.y,r.size.width,r.size.height);assert(!CGRectIntersectsRect(frame,previous));}
            [frames addObject:[NSValue valueWithRect:NSMakeRect(frame.origin.x,frame.origin.y,frame.size.width,frame.size.height)]];}
        layouts++;}
    NSMutableDictionary *bad=[@{@"schema":@3,@"lookSensitivity":@999,@"joystickRadius":@1,@"buttons":@{@"edit":@{@"visible":@NO,@"binding":@"RT"},@"fire":@{@"binding":@"invalid",@"scale":@999,@"opacity":@0,@"x":@(-100),@"y":@99}}} mutableCopy];
    NSMutableDictionary *checked=CPTouchValidatedLayout(bad);assert([checked[@"lookSensitivity"] doubleValue]==5 && [checked[@"joystickRadius"] doubleValue]==28);
    assert([checked[@"buttons"][@"edit"][@"visible"] boolValue] && [checked[@"buttons"][@"edit"][@"binding"] isEqual:@"ui.edit"]);
    assert([checked[@"buttons"][@"fire"][@"binding"] isEqual:@"RT"] && [checked[@"buttons"][@"fire"][@"scale"] doubleValue]==1.65 && [checked[@"buttons"][@"fire"][@"opacity"] doubleValue]==0.25);
    layout[@"buttons"][@"fire"][@"binding"]=@"A";layout[@"buttons"][@"fire"][@"x"]=@0.62;layout[@"buttons"][@"fire"][@"y"]=@0.72;layout[@"lookSensitivity"]=@2.4;
    NSData *encoded=[NSJSONSerialization dataWithJSONObject:layout options:0 error:nil];NSMutableDictionary *round=CPTouchValidatedLayout([NSJSONSerialization JSONObjectWithData:encoded options:0 error:nil]);
    assert([round isEqual:layout]);assert(!CPTouchShouldHide(10,6,4));assert(CPTouchShouldHide(10,6,0));
    NSDictionary *report=@{@"passed":@YES,@"fourIndependentContactRolesPassed":@YES,@"crossingMidlineDoesNotStealGesture":@YES,@"additionalBlankFingerDoesNotStealGesture":@YES,
        @"stationaryLookChecks":@600,@"sameDisplacementDifferentSampleCounts":@(splitCases),@"defaultNoOverlapLayouts":@(layouts),@"completeNativeButtons":@(native.count),@"bilingualBindingCount":@(CPTouchBindings().count),
        @"savedLayoutBindingAndSensitivityRoundTripPassed":@YES,@"malformedLayoutSanitized":@YES,@"scope":@"Production router and layout model on ARM64 Mac; no OS multi-finger injection or game loaded",@"physicalTouchGameplayVerified":@NO};
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];[data writeToFile:@(argv[1]) atomically:YES];puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}}
