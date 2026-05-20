//
//  stress_main.mm
//  AppleTrace batched-writer stress harness.
//
//  Spawns several worker threads that each emit a fixed number of
//  begin/end pairs, then flushes. Worker threads exit before the flush so the
//  pthread-key drain path is exercised alongside the cross-thread APTFlush.
//  The accompanying script asserts that exactly threads*per_thread "stress"
//  complete events survive (no loss, no duplication).
//

#import <Foundation/Foundation.h>

#include <cstdio>
#include <thread>
#include <vector>

#import "appletrace.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        const int thread_count = 8;
        const int pairs_per_thread = 25000;

        std::vector<std::thread> workers;
        workers.reserve(thread_count);
        for (int t = 0; t < thread_count; ++t) {
            workers.emplace_back([pairs_per_thread]() {
                for (int i = 0; i < pairs_per_thread; ++i) {
                    APTBeginSection("stress");
                    APTEndSection("stress");
                }
            });
        }
        for (std::thread &worker : workers) {
            worker.join();  // thread exit triggers the per-thread drain path
        }

        // Smoke the other event types (not counted by the assertion).
        APTInstant("stress_done");
        APTCounter("stress_threads", thread_count);
        APTAsyncBegin("stress_async", 1);
        APTAsyncEnd("stress_async", 1);

        APTFlush();
        APTSyncWait();

        const long expected = (long)thread_count * pairs_per_thread;
        fprintf(stdout, "EXPECTED_STRESS_PAIRS=%ld\n", expected);
    }
    return 0;
}
