//
//  AppDelegate.m
//  ManualSectionDemo
//
//  Created by everettjf on 21/09/2017.
//  Copyright © 2017 everettjf. All rights reserved.
//

#import "AppDelegate.h"
#import "appletrace.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSLog(@"AppleTrace trace directory: %s", APTGetTraceDirectory());
    // The actual showcase workload lives in ViewController (tap "Generate
    // Trace"). Mark launch so the very first slice in the timeline is obvious.
    APTInstant("app_did_launch");
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // The trace writer batches events per thread and ships them on a size
    // threshold, on APTFlush(), or at thread exit (docs/perf-batching-design.md).
    // Flush here so a trace is always on disk when the app is backgrounded.
    APTFlush();
}

- (void)applicationWillTerminate:(UIApplication *)application {
    APTFlush();
}

@end
