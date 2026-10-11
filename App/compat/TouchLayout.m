#import "TouchLayout.h"
#include <math.h>
static NSDictionary *Binding(NSString *identifier,NSString *title,NSString *code,NSString *symbol,NSNumber *key) {
    static NSDictionary *english;static dispatch_once_t once;dispatch_once(&once,^{english=@{
        @"A":@"Jump / Confirm",@"B":@"Crouch / Dodge",@"X":@"Interact / Reload",@"Y":@"Weapon swap",
        @"LT":@"Aim / Brake",@"RT":@"Fire / Accelerate",@"LB":@"Scan",@"RB":@"Gadget / Throw",
        @"L3":@"Sprint / L3",@"R3":@"Melee / R3",@"up":@"Quick slot ↑",@"down":@"Quick slot ↓",@"left":@"Quick slot ←",@"right":@"Quick slot →",
        @"menu":@"Menu / Pause",@"options":@"Panel / Back",@"map":@"Map",@"inventory":@"Inventory",@"journal":@"Journal",
        @"confirm":@"Continue / Enter",@"phone":@"Phone",@"vehicle":@"Call vehicle",@"escape":@"Back / Esc",@"save":@"Quick save"
    };});
    return @{@"id":identifier,@"title":title,@"title_en":english[identifier] ?: code,@"code":code,@"symbol":symbol,@"key":key ?: @(-1)};
}
NSArray<NSDictionary *> *CPTouchBindings(void) {
    static NSArray *values;static dispatch_once_t once;dispatch_once(&once,^{values=@[
        Binding(@"A",@"跳跃 / 确认",@"A",@"figure.jumprope",nil),Binding(@"B",@"蹲伏 / 闪避",@"B",@"figure.flexibility",nil),
        Binding(@"X",@"交互 / 装填",@"X",@"hand.tap",nil),Binding(@"Y",@"切换武器",@"Y",@"arrow.triangle.2.circlepath",nil),
        Binding(@"LT",@"瞄准 / 刹车",@"LT",@"scope",nil),Binding(@"RT",@"射击 / 加速",@"RT",@"burst.fill",nil),
        Binding(@"LB",@"扫描",@"LB",@"viewfinder",nil),Binding(@"RB",@"投掷 / 装置",@"RB",@"circle.hexagongrid.fill",nil),
        Binding(@"L3",@"冲刺 / L3",@"L3",@"figure.run",nil),Binding(@"R3",@"近战 / R3",@"R3",@"bolt.shield",nil),
        Binding(@"up",@"方向 / 快捷 ↑",@"↑",@"arrow.up",nil),Binding(@"down",@"方向 / 快捷 ↓",@"↓",@"arrow.down",nil),
        Binding(@"left",@"方向 / 快捷 ←",@"←",@"arrow.left",nil),Binding(@"right",@"方向 / 快捷 →",@"→",@"arrow.right",nil),
        Binding(@"menu",@"菜单 / 暂停",@"MENU",@"line.3.horizontal",nil),Binding(@"options",@"面板 / 返回",@"VIEW",@"rectangle.on.rectangle",nil),
        Binding(@"map",@"地图",@"M",@"map",@46),Binding(@"inventory",@"物品",@"I",@"shippingbox",@34),
        Binding(@"journal",@"日志",@"J",@"list.bullet.rectangle",@38),Binding(@"confirm",@"继续 / 回车",@"↵",@"return",@36),
        Binding(@"phone",@"电话",@"T",@"phone",@17),Binding(@"vehicle",@"呼叫载具",@"V",@"car",@9),
        Binding(@"escape",@"返回 / Esc",@"ESC",@"arrow.uturn.backward",@53),Binding(@"save",@"快速存档",@"F5",@"square.and.arrow.down",@96)
    ];});return values;
}
NSDictionary *CPTouchBinding(NSString *identifier){for(NSDictionary *b in CPTouchBindings())if([b[@"id"] isEqual:identifier])return b;return nil;}
static NSDictionary *Button(NSString *identifier,NSString *binding,NSString *anchor,double x,double y,double width,double height,BOOL visible) {
    return @{@"id":identifier,@"binding":binding,@"anchor":anchor,@"dx":@(x),@"dy":@(y),@"width":@(width),@"height":@(height),@"visible":@(visible)};
}
NSArray<NSDictionary *> *CPTouchButtons(void) {
    static NSArray *values;static dispatch_once_t once;dispatch_once(&once,^{values=@[
        Button(@"aim",@"LT",@"LT",52,70,62,60,YES),Button(@"fire",@"RT",@"RT",-52,70,68,64,YES),
        Button(@"scan",@"LB",@"LT",52,130,48,46,YES),Button(@"gadget",@"RB",@"RT",-130,94,48,46,YES),
        Button(@"jump",@"A",@"RB",-50,-60,60,58,YES),Button(@"crouch",@"B",@"RB",-50,-134,52,50,YES),
        Button(@"interact",@"X",@"RB",-122,-70,56,54,YES),Button(@"weapon",@"Y",@"RB",-122,-148,50,48,YES),
        Button(@"sprint",@"L3",@"LB",144,-48,46,44,YES),Button(@"melee",@"R3",@"RB",-192,-108,46,44,YES),
        Button(@"dpad-up",@"up",@"LB",72,-169,38,38,YES),Button(@"dpad-down",@"down",@"LB",72,-91,38,38,YES),
        Button(@"dpad-left",@"left",@"LB",27,-130,38,38,YES),Button(@"dpad-right",@"right",@"LB",117,-130,38,38,YES),
        Button(@"view",@"options",@"CT",-180,23,48,34,NO),Button(@"menu",@"menu",@"CT",-120,23,48,34,YES),
        Button(@"map",@"map",@"CT",-60,23,48,34,YES),Button(@"inventory",@"inventory",@"CT",0,23,48,34,YES),
        Button(@"journal",@"journal",@"CT",60,23,48,34,YES),
        Button(@"mode",@"ui.mode",@"CT",120,23,50,34,YES),Button(@"edit",@"ui.edit",@"CT",180,23,50,34,YES)
    ];});return values;
}
NSMutableDictionary *CPTouchDefaultLayout(void) {
    NSMutableDictionary *buttons=[NSMutableDictionary new];
    for(NSDictionary *b in CPTouchButtons())buttons[b[@"id"]]=[@{@"binding":b[@"binding"],@"scale":@1,@"opacity":@0.76,@"visible":b[@"visible"]} mutableCopy];
    return [@{@"schema":@3,@"buttons":buttons,@"lookSensitivity":@1.6,@"aimSensitivity":@0.65,@"invertLookY":@NO,@"joystickRadius":@46} mutableCopy];
}
static double Number(id value,double fallback,double low,double high) {
    if(![value isKindOfClass:NSNumber.class])return fallback;
    double number=[value doubleValue];return isfinite(number)?MAX(low,MIN(high,number)):fallback;
}
NSMutableDictionary *CPTouchValidatedLayout(id source) {
    NSMutableDictionary *result=CPTouchDefaultLayout();
    if(![source isKindOfClass:NSDictionary.class] || ![source[@"schema"] isEqual:@3])return result;
    result[@"lookSensitivity"]=@(Number(source[@"lookSensitivity"],1.6,0.2,5));
    result[@"aimSensitivity"]=@(Number(source[@"aimSensitivity"],0.65,0.15,1.5));
    result[@"joystickRadius"]=@(Number(source[@"joystickRadius"],46,28,90));
    if([source[@"invertLookY"] isKindOfClass:NSNumber.class])result[@"invertLookY"]=@([source[@"invertLookY"] boolValue]);
    NSDictionary *saved=source[@"buttons"];if(![saved isKindOfClass:NSDictionary.class])return result;
    for(NSDictionary *definition in CPTouchButtons()) {
        NSString *identifier=definition[@"id"];NSDictionary *entry=saved[identifier];if(![entry isKindOfClass:NSDictionary.class])continue;
        NSMutableDictionary *value=result[@"buttons"][identifier];BOOL system=[definition[@"binding"] hasPrefix:@"ui."];
        if(!system && [entry[@"binding"] isKindOfClass:NSString.class] && CPTouchBinding(entry[@"binding"]))value[@"binding"]=entry[@"binding"];
        value[@"scale"]=@(Number(entry[@"scale"],1,0.7,1.65));value[@"opacity"]=@(Number(entry[@"opacity"],0.76,0.25,1));
        if(!system && [entry[@"visible"] isKindOfClass:NSNumber.class])value[@"visible"]=@([entry[@"visible"] boolValue]);
        // System access stays available, even after hiding every gameplay key.
        if(system)value[@"visible"]=@YES;
        if([entry[@"x"] isKindOfClass:NSNumber.class] && [entry[@"y"] isKindOfClass:NSNumber.class]) {
            value[@"x"]=@(Number(entry[@"x"],0.5,0,1));value[@"y"]=@(Number(entry[@"y"],0.5,0,1));
        }
    }return result;
}
CGRect CPTouchButtonFrame(NSDictionary *definition,NSDictionary *setting,CGRect area) {
    double unit=MAX(0.80,MIN(1.25,area.size.height/360.0));double scale=[setting[@"scale"] doubleValue]*unit;
    double width=MAX(38,[definition[@"width"] doubleValue]*scale),height=MAX(34,[definition[@"height"] doubleValue]*scale);
    NSString *anchor=definition[@"anchor"];double ax=[anchor hasPrefix:@"R"]?1:([anchor hasPrefix:@"C"]?0.5:0),ay=[anchor hasSuffix:@"B"]?1:0;
    double x=area.origin.x+ax*area.size.width+[definition[@"dx"] doubleValue]*unit;
    double y=area.origin.y+ay*area.size.height+[definition[@"dy"] doubleValue]*unit;
    if(setting[@"x"] && setting[@"y"]){x=area.origin.x+[setting[@"x"] doubleValue]*area.size.width;y=area.origin.y+[setting[@"y"] doubleValue]*area.size.height;}
    x=MAX(CGRectGetMinX(area)+width/2+2,MIN(CGRectGetMaxX(area)-width/2-2,x));
    y=MAX(CGRectGetMinY(area)+height/2+2,MIN(CGRectGetMaxY(area)-height/2-2,y));
    return CGRectMake(x-width/2,y-height/2,width,height);
}
NSString *CPTouchLayoutPath(void){return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/CP2077Touch/layout-v3.json"];}
