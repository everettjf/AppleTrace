#import <Foundation/Foundation.h>
#import "appletrace.h"
#import "AgentTransport.h"

static BOOL enabled = NO;
static BOOL flushed = NO;
static NSString *allowFilter = nil;
static NSString *denyFilter = nil;

BOOL APTStartCapture(void) { enabled = YES; return YES; }
void APTStopCapture(void) { enabled = NO; }
APTCaptureState APTGetCaptureState(void) { return enabled ? APTCaptureStateRecording : APTCaptureStateIdle; }
void APTGetTraceMetrics(APTTraceMetrics *metrics) { if (metrics) *metrics = (APTTraceMetrics){3, 4, 0}; }
void APTFlush(void) { flushed = YES; }
void APTSetObjcTraceClassFilters(const char *allow, const char *deny) {
    allowFilter = allow ? [NSString stringWithUTF8String:allow] : nil;
    denyFilter = deny ? [NSString stringWithUTF8String:deny] : nil;
}

int main(void) {
    @autoreleasepool {
        APTStartAgentTransport();
        for (NSInteger attempt = 0; attempt < 200; attempt++) {
            if (!enabled && flushed && [allowFilter isEqualToString:@"APTAllowed"] &&
                [denyFilter isEqualToString:@"APTDeny"]) break;
            [NSThread sleepForTimeInterval:0.02];
        }
        return !enabled && flushed && [allowFilter isEqualToString:@"APTAllowed"] &&
                       [denyFilter isEqualToString:@"APTDeny"]
                   ? 0
                   : 2;
    }
}
