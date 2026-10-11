#import "GamePacing.h"

static BOOL CPUpdateSettings(NSMutableDictionary *settings,NSDictionary *updates,NSMutableArray *changes,NSError **error) {
    NSMutableSet *found=[NSMutableSet new];
    if(![settings[@"data"] isKindOfClass:NSArray.class])return NO;
    for(id group in settings[@"data"]) {
        if(![group isKindOfClass:NSDictionary.class] || ![group[@"options"] isKindOfClass:NSArray.class])return NO;
        for(NSMutableDictionary *option in group[@"options"]) {
            if(![option isKindOfClass:NSMutableDictionary.class])return NO;
            id replacement=updates[option[@"name"]];if(!replacement)continue;
            [found addObject:option[@"name"]];
            NSArray *values=option[@"values"];
            if((values && (![values isKindOfClass:NSArray.class] || ![values containsObject:replacement])) ||
               ([option[@"type"] isEqual:@"int"] && option[@"min_value"] && option[@"max_value"] &&
                ([replacement doubleValue]<[option[@"min_value"] doubleValue] || [replacement doubleValue]>[option[@"max_value"] doubleValue]))) {
                if(error)*error=[NSError errorWithDomain:@"CPGamePacing" code:1 userInfo:@{NSLocalizedDescriptionKey:[@"Unsupported setting: " stringByAppendingString:option[@"name"]]}];return NO;
            }
            if(![option[@"value"] isEqual:replacement])
                [changes addObject:@{@"name":option[@"name"],@"before":option[@"value"] ?: NSNull.null,@"after":replacement}];
            option[@"value"]=replacement;
            if(values)option[@"index"]=@([values indexOfObject:replacement]);
        }
    }
    if(found.count!=updates.count) {
        if(error)*error=[NSError errorWithDomain:@"CPGamePacing" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Required mobile setting is missing; original file was not written"}];
        return NO;
    }return YES;
}

BOOL CPApplyGamePacing(NSMutableDictionary *settings,NSString *resolution,NSMutableArray *changes,NSError **error) {
    return CPUpdateSettings(settings,@{@"Resolution":resolution,@"MaximumFPS_OnOff":@YES,
        @"MaximumFPS_Value":@30,@"DRS_TargetFPS":@30},changes,error);
}
BOOL CPApplyMobilePacing(NSMutableDictionary *settings,NSString *resolution,NSUInteger drsMinimum,NSMutableArray *changes,NSError **error) {
    return CPApplyDevicePacing(settings,resolution,drsMinimum,50,changes,error);
}
BOOL CPApplyDevicePacing(NSMutableDictionary *settings,NSString *resolution,NSUInteger drsMinimum,NSUInteger drsMaximum,NSMutableArray *changes,NSError **error) {
    if(drsMinimum<40 || drsMinimum>50 || drsMaximum<drsMinimum || drsMaximum>100)return NO;
    for(NSMutableDictionary *group in settings[@"data"])for(NSMutableDictionary *option in group[@"options"])
        if(([option[@"name"] isEqual:@"DRS_MinResolution"] || [option[@"name"] isEqual:@"DRS_MaxResolution"]) &&
           [option[@"min_value"] isEqual:@50])option[@"min_value"]=@(drsMinimum);
    // The native CAMetalDisplayLink/semaphore render loop already requests 30
    // Hz. Avoid an additional independent engine sleep deadline before it.
    BOOL result=CPUpdateSettings(settings,@{@"Resolution":resolution,@"MaximumFPS_OnOff":@NO,
        @"MaximumFPS_Value":@30,@"DRS_TargetFPS":@30,@"FrameGeneration":@"Off",
        @"FSR3_FrameGeneration":@NO,@"ResolutionScaling":@"FSR2",@"DynamicResolutionScaling":@YES,
        @"DRS_MinResolution":@(drsMinimum),@"DRS_MaxResolution":@(drsMaximum),@"FSR2":@"Dynamic",
        @"VSync":@"UI-Settings-Video-QualitySetting-Off",@"HDDMode":@"Off"},changes,error);
    if(result)for(NSMutableDictionary *group in settings[@"data"])for(NSMutableDictionary *option in group[@"options"])
        if([option[@"name"] isEqual:@"VSync"] && ![option[@"index"] isEqual:@0]) {
            [changes addObject:@{@"name":@"VSync/index",@"before":option[@"index"] ?: NSNull.null,@"after":@0}];
            option[@"index"]=@0;
        }
    if(result)for(NSMutableDictionary *group in settings[@"data"])for(NSMutableDictionary *option in group[@"options"])
        if([option[@"name"] isEqual:@"Resolution"]) {
            NSNumber *index=[resolution hasSuffix:@"x1080"]?@3:@1;
            if(![option[@"index"] isEqual:index])[changes addObject:@{@"name":@"Resolution/index",@"before":option[@"index"] ?: NSNull.null,@"after":index}];
            option[@"index"]=index;
        }
    return result;
}

NSMutableDictionary *CPInitialMobileSettings(NSDictionary *schema,NSError **error) {
    // A fresh device needs only the mobile overrides; absent options continue
    // using engine defaults. Build from the exact game schema, not user data.
    if(![schema[@"version"] isEqual:@140] || ![schema[@"options"] isKindOfClass:NSArray.class])return nil;
    NSSet *names=[NSSet setWithArray:@[@"Resolution",@"MaximumFPS_OnOff",@"MaximumFPS_Value",@"DRS_TargetFPS",@"FrameGeneration",@"FSR3_FrameGeneration",@"ResolutionScaling",@"DynamicResolutionScaling",@"DRS_MinResolution",@"DRS_MaxResolution",@"FSR2",@"VSync",@"HDDMode"]];
    NSArray *keys=@[@"name",@"type",@"is_dynamic",@"value",@"default_value",@"index",@"default_index",@"values",@"min_value",@"max_value",@"step_value"];
    NSMutableArray *groups=[NSMutableArray new];NSMutableSet *found=[NSMutableSet new];
    for(NSDictionary *group in schema[@"options"]) {
        if(![group isKindOfClass:NSDictionary.class] || ![group[@"options"] isKindOfClass:NSArray.class] || ![group[@"group_name"] isKindOfClass:NSString.class])return nil;
        NSMutableArray *options=[NSMutableArray new];
        for(NSDictionary *original in group[@"options"]) {
            if(![original isKindOfClass:NSDictionary.class])return nil;
            if(![names containsObject:original[@"name"]])continue;
            NSMutableDictionary *option=[NSMutableDictionary new];for(NSString *key in keys)if(original[key])option[key]=[original[key] copy];
            if(!option[@"value"] && [option[@"values"] isKindOfClass:NSArray.class]) {
                NSUInteger index=[option[@"index"] unsignedIntegerValue];if(index>=[option[@"values"] count])return nil;option[@"value"]=option[@"values"][index];
            }
            if([option[@"name"] isEqual:@"Resolution"]) {option[@"value"]=@"1280x720";option[@"index"]=@1;}
            if([option[@"name"] isEqual:@"VSync"]) {option[@"value"]=@"UI-Settings-Video-QualitySetting-Off";option[@"index"]=@0;}
            if(!option[@"value"])return nil;[found addObject:option[@"name"]];[options addObject:option];
        }
        if(options.count)[groups addObject:[@{@"group_name":group[@"group_name"],@"options":options} mutableCopy]];
    }
    if(found.count!=names.count) {
        if(error)*error=[NSError errorWithDomain:@"CPGamePacing" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Original game schema is missing required mobile settings"}];return nil;
    }
    return [@{@"version":@140,@"data":groups} mutableCopy];
}
