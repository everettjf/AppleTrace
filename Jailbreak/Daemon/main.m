#import "AgentRegistry.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *socketPath = NSProcessInfo.processInfo.environment[@"APPLETRACE_DAEMON_SOCKET"];
        if (!socketPath.length) {
            socketPath = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]
                             ? @"/var/jb/var/run/appletraced.sock"
                             : @"/var/run/appletraced.sock";
        }
        APTAgentRegistry *registry = [[APTAgentRegistry alloc] initWithSocketPath:socketPath];
        NSError *error = nil;
        if (![registry run:&error]) {
            NSLog(@"appletraced failed: %@", error);
            return 1;
        }
    }
    return 0;
}
