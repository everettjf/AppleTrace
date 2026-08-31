#import <Foundation/Foundation.h>
#import "appletrace.h"
#import "AgentTransport.h"

static BOOL enabled = NO;

BOOL APTStartCapture(void) { enabled = YES; return YES; }
void APTStopCapture(void) { enabled = NO; }
APTCaptureState APTGetCaptureState(void) { return enabled ? APTCaptureStateRecording : APTCaptureStateIdle; }
void APTGetTraceMetrics(APTTraceMetrics *metrics) { if (metrics) *metrics = (APTTraceMetrics){3, 4, 0}; }
void APTFlush(void) {}
void APTSetObjcTraceClassFilters(const char *allow, const char *deny) { (void)allow; (void)deny; }

int main(void) {
    @autoreleasepool {
        APTStartAgentTransport();
        for (NSInteger attempt = 0; attempt < 100 && !enabled; attempt++) {
            [NSThread sleepForTimeInterval:0.02];
        }
        return enabled ? 0 : 2;
    }
}
