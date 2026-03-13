//
//  AppDelegate.m
//  TraceAllMsgDemo
//
//  Created by everettjf on 21/09/2017.
//  Copyright © 2017 everettjf. All rights reserved.
//

#import "AppDelegate.h"
#import <appletrace/appletrace.h>
#import <fcntl.h>
#import <limits.h>
#import <string.h>
#import <unistd.h>
#import "ViewController.h"
#import "ThreadTest.h"

@interface AppDelegate ()
@property (nonatomic, assign) BOOL didStartTraceScenario;

@end

@implementation AppDelegate

static BOOL APTBoolFromEnvironment(NSString *key) {
    NSString *value = [[[NSProcessInfo processInfo] environment] objectForKey:key];
    if (!value.length) {
        return NO;
    }

    NSString *normalized = value.lowercaseString;
    return ![normalized isEqualToString:@"0"] &&
           ![normalized isEqualToString:@"false"] &&
           ![normalized isEqualToString:@"no"];
}

static BOOL APTProcessHasArgument(NSString *argument) {
    return [[[NSProcessInfo processInfo] arguments] containsObject:argument];
}

static BOOL APTExperimentalMarkerExists(void) {
    NSString *libraryPath = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *markerPath = [libraryPath stringByAppendingPathComponent:@"appletrace_experimental.flag"];
    return [[NSFileManager defaultManager] fileExistsAtPath:markerPath];
}

static void APTAppendScenarioProgress(const char *step) {
    if (!step) {
        return;
    }

    const char *home = getenv("HOME");
    if (!home || home[0] == '\0') {
        return;
    }

    char progressPath[PATH_MAX];
    int written = snprintf(progressPath,
                           sizeof(progressPath),
                           "%s/Library/appletracedata/scenario-progress.log",
                           home);
    if (written <= 0 || written >= (int)sizeof(progressPath)) {
        return;
    }

    int fd = open(progressPath, O_CREAT | O_WRONLY | O_APPEND, 0644);
    if (fd < 0) {
        return;
    }

    (void)write(fd, step, strlen(step));
    (void)write(fd, "\n", 1);
    (void)close(fd);
    (void)write(STDERR_FILENO, "AppleTrace progress: ", 21);
    (void)write(STDERR_FILENO, step, strlen(step));
    (void)write(STDERR_FILENO, "\n", 1);
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    NSLog(@"AppleTrace trace directory: %s", APTGetTraceDirectory());
    NSTimeInterval t = [UIApplication sharedApplication].backgroundTimeRemaining;
    NSLog(@"%@",@(t));
    [self scheduleTraceScenarioIfNeeded];

    return YES;
}
- (void)myTest{
//    NSLog(@"my test");
}

- (void)levelOne{
    usleep(50);
    [self levelTwo];
}

- (void)levelTwo{
    usleep(50);
    [self levelThree];
}

- (void)levelThree{
    usleep(50);
    
    [[self class]staticMethod:@"hi"];
}

+ (BOOL)staticMethod:(NSString*)words{
    usleep(100);
    return YES;
}





- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}


- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    APTFlush();
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [self scheduleTraceScenarioIfNeeded];
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    APTFlush();
}

- (void)runTraceScenario {
    APTAppendScenarioProgress("runTraceScenario:entry");
    NSLog(@"AppleTrace experimental scenario started");
    APTAppendScenarioProgress("runTraceScenario:after-log");
    APTBeginSection("appletrace-experimental-scenario");
    APTAppendScenarioProgress("runTraceScenario:after-experimental-begin");
    APTBeginSection("appletrace-smoke-scenario");
    APTAppendScenarioProgress("runTraceScenario:after-smoke-begin");
    [self myTest];
    APTAppendScenarioProgress("runTraceScenario:after-myTest");
    usleep(200);
    APTAppendScenarioProgress("runTraceScenario:after-usleep");

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        APTAppendScenarioProgress("runTraceScenario:block1-entry");
        ThreadTest *t = [[ThreadTest alloc] init];
        APTAppendScenarioProgress("runTraceScenario:block1-after-alloc");
        [t go];
        APTAppendScenarioProgress("runTraceScenario:block1-after-go");
        APTFlush();
        APTAppendScenarioProgress("runTraceScenario:block1-after-flush");
    });

    APTAppendScenarioProgress("runTraceScenario:before-levelOne");
    [self levelOne];
    APTAppendScenarioProgress("runTraceScenario:after-levelOne");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        APTAppendScenarioProgress("runTraceScenario:block2-entry");
        APTEndSection("appletrace-smoke-scenario");
        APTAppendScenarioProgress("runTraceScenario:block2-after-smoke-end");
        APTEndSection("appletrace-experimental-scenario");
        APTAppendScenarioProgress("runTraceScenario:block2-after-experimental-end");
        APTSyncWait();
        APTAppendScenarioProgress("runTraceScenario:block2-after-sync");
        APTFlush();
        APTAppendScenarioProgress("runTraceScenario:block2-after-flush");
    });
}

- (void)scheduleTraceScenarioIfNeeded {
    if (self.didStartTraceScenario) {
        return;
    }

    self.didStartTraceScenario = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL shouldRunExperimental = APTBoolFromEnvironment(@"APPLETRACE_EXPERIMENTAL_SCENARIO") ||
                                     APTProcessHasArgument(@"-AppleTraceExperimentalScenario") ||
                                     APTExperimentalMarkerExists();
        NSLog(@"AppleTrace experimental requested: %@", shouldRunExperimental ? @"YES" : @"NO");
        BOOL installed = APTInstallObjcMsgSendHook();
        if (installed) {
            APTBeginSection("appletrace-smoke-scenario");
            APTEndSection("appletrace-smoke-scenario");
            APTSyncWait();

            if (shouldRunExperimental) {
                [self runTraceScenario];
            }
        }
    });
}


@end
