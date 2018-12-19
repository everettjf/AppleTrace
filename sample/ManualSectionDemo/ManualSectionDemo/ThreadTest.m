//
//  ThreadTest.m
//  ManualSectionDemo
//
//  Created by everettjf on 2017/9/19.
//  Copyright © 2017年 everettjf. All rights reserved.
//

#import "ThreadTest.h"
#import "appletrace.h"

@implementation ThreadTest

- (void)go{
    APTBegin;
    usleep(20);
    
    [self goOne];
    
    APTEnd;
}

- (void)goOne{
    APTBegin;
    [self goTwo];
    APTEnd;
}

- (void)goTwo{
    APTBegin;
    for(int i=0;i<10;i++){
        [self goLoop];
    }
    APTEnd;
}

- (void)goLoop{
    APTBegin;
    usleep(20);
    APTEnd;
}

@end
