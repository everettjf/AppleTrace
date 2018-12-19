//
//  appletrace.h
//  appletrace
//
//  Created by everettjf on 2017/9/12.
//  Copyright © 2017年 everettjf. All rights reserved.
//


#import <Foundation/Foundation.h>

FOUNDATION_EXPORT void APTBeginSection(const char* name);
FOUNDATION_EXPORT void APTEndSection(const char* name);
FOUNDATION_EXPORT void APTSyncWait(void);

// Objective C class method
#define APTBegin APTBeginSection([NSString stringWithFormat:@"[%@]%@",self,NSStringFromSelector(_cmd)].UTF8String)
#define APTEnd APTEndSection([NSString stringWithFormat:@"[%@]%@",self,NSStringFromSelector(_cmd)].UTF8String)
