//
//  AppDelegate.m
//  ManualSectionDemo
//
//  Created by everettjf on 21/09/2017.
//  Copyright © 2017 everettjf. All rights reserved.
//

#import "AppDelegate.h"
#import "appletrace.h"
#import "ThreadTest.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    APTBegin;
    
    usleep(300);
    
    [self myTest];
    
    usleep(200);
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        APTBeginSection("dispatch_global");
        ThreadTest *t = [[ThreadTest alloc]init];
        [t go];
        APTEndSection("dispatch_global");
    });

    [self levelOne];
    
    APTEnd;
    return YES;
}
- (void)myTest{
    APTBegin;
    NSLog(@"my test");
    usleep(400);
    APTEnd;
}

- (void)levelOne{
    APTBegin;
    
    usleep(50);
    [self levelTwo];
    APTEnd;
}

- (void)levelTwo{
    APTBegin;
    
    usleep(50);
    [self levelThree];
    APTEnd;
}

- (void)levelThree{
    APTBegin;
    
    usleep(50);
    
    [[self class]staticMethod:@"hi"];
    
    APTEnd;
}

+ (BOOL)staticMethod:(NSString*)words{
    APTBegin;
    
    usleep(100);
    
    APTEnd;
    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}


@end
