#import "AgentRegistry.h"

#import <arpa/inet.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import <unistd.h>

typedef struct __attribute__((packed)) APTAgentFrameHeader {
    uint32_t magic;
    uint16_t version;
    uint16_t type;
    uint32_t payloadLength;
} APTAgentFrameHeader;

static const uint32_t APTAgentFrameMagic = 0x41505431;
static const uint32_t APTAgentMaximumPayload = 1024 * 1024;

static BOOL APTDaemonWriteAll(int socketFD, const void *bytes, size_t length) {
    const uint8_t *cursor = bytes;
    while (length > 0) {
        ssize_t written = write(socketFD, cursor, length);
        if (written <= 0) return NO;
        cursor += written;
        length -= (size_t)written;
    }
    return YES;
}

@interface APTAgentRegistry ()
@property(nonatomic, copy) NSString *socketPath;
@end

@implementation APTAgentRegistry

- (instancetype)initWithSocketPath:(NSString *)socketPath {
    self = [super init];
    if (self) _socketPath = [socketPath copy];
    return self;
}

- (BOOL)run:(NSError **)error {
    NSString *directory = self.socketPath.stringByDeletingLastPathComponent;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0755}
                                                    error:error];
    unlink(self.socketPath.fileSystemRepresentation);

    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listener < 0) return NO;
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, self.socketPath.fileSystemRepresentation, sizeof(address.sun_path));
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(listener, 32) != 0) {
        close(listener);
        return NO;
    }
    chmod(self.socketPath.fileSystemRepresentation, 0660);

    for (;;) {
        int client = accept(listener, NULL, NULL);
        if (client < 0) continue;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [self handleClient:client];
        });
    }
}

- (void)handleClient:(int)client {
    @autoreleasepool {
        APTAgentFrameHeader header = {0};
        ssize_t count = recv(client, &header, sizeof(header), MSG_WAITALL);
        uint32_t length = ntohl(header.payloadLength);
        if (count != sizeof(header) || ntohl(header.magic) != APTAgentFrameMagic ||
            ntohs(header.version) != 1 || ntohs(header.type) != 1 ||
            length > APTAgentMaximumPayload) {
            close(client);
            return;
        }
        NSMutableData *payload = [NSMutableData dataWithLength:length];
        if (length && recv(client, payload.mutableBytes, length, MSG_WAITALL) != length) {
            close(client);
            return;
        }
        NSDictionary *hello = [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil];
        NSLog(@"AppleTrace agent connected: %@", hello);

        // Used by the host IPC smoke test to exercise the daemon-to-Agent
        // command direction without exposing an additional production API.
        NSString *testCommand = NSProcessInfo.processInfo.environment[@"APPLETRACE_TEST_COMMAND"];
        if (testCommand.length) {
            NSData *commandData = [NSJSONSerialization dataWithJSONObject:@{@"command": testCommand}
                                                                   options:0
                                                                     error:nil];
            APTAgentFrameHeader commandHeader = {
                .magic = htonl(APTAgentFrameMagic),
                .version = htons(1),
                .type = htons(2),
                .payloadLength = htonl((uint32_t)commandData.length),
            };
            APTDaemonWriteAll(client, &commandHeader, sizeof(commandHeader));
            APTDaemonWriteAll(client, commandData.bytes, commandData.length);
        }

        // Phase 3 keeps the connection alive and validates Agent framing. The
        // Phase 4 session broker owns command fan-out and Web API integration.
        uint8_t buffer[256];
        while (read(client, buffer, sizeof(buffer)) > 0) {}
        close(client);
    }
}

@end
