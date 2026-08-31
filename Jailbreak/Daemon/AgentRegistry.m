#import "AgentRegistry.h"

#import <arpa/inet.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import <pwd.h>
#import <unistd.h>

typedef NS_ENUM(uint16_t, APTAgentMessageType) {
    APTAgentMessageHello = 1,
    APTAgentMessageCommand = 2,
    APTAgentMessageStatus = 3,
    APTAgentMessageHeartbeat = 4,
    APTAgentMessageError = 5,
};

typedef struct __attribute__((packed)) APTAgentFrameHeader {
    uint32_t magic;
    uint16_t version;
    uint16_t type;
    uint32_t payloadLength;
} APTAgentFrameHeader;

static const uint32_t APTAgentFrameMagic = 0x41505431;
static const uint16_t APTAgentProtocolVersion = 1;
static const uint32_t APTAgentMaximumPayload = 1024 * 1024;

static NSError *APTAgentError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"com.everettjf.appletrace.agent"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL APTReadAll(int socketFD, void *bytes, size_t length) {
    uint8_t *cursor = bytes;
    while (length > 0) {
        ssize_t count = read(socketFD, cursor, length);
        if (count <= 0) return NO;
        cursor += count;
        length -= (size_t)count;
    }
    return YES;
}

static BOOL APTWriteAll(int socketFD, const void *bytes, size_t length) {
    const uint8_t *cursor = bytes;
    while (length > 0) {
        ssize_t written = write(socketFD, cursor, length);
        if (written <= 0) return NO;
        cursor += written;
        length -= (size_t)written;
    }
    return YES;
}

static NSDictionary *APTReadJSONFrame(int socketFD, APTAgentMessageType *type) {
    APTAgentFrameHeader header = {0};
    if (!APTReadAll(socketFD, &header, sizeof(header))) return nil;
    uint32_t length = ntohl(header.payloadLength);
    if (ntohl(header.magic) != APTAgentFrameMagic ||
        ntohs(header.version) != APTAgentProtocolVersion ||
        length > APTAgentMaximumPayload) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (length && !APTReadAll(socketFD, data.mutableBytes, length)) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    if (type) *type = (APTAgentMessageType)ntohs(header.type);
    return value;
}

@interface APTAgentSession : NSObject
@property(nonatomic, readonly) NSString *identifier;
@property(nonatomic, readonly) int socketFD;
@property(nonatomic, copy) NSDictionary *status;
@property(nonatomic, strong) NSDate *connectedAt;
@property(nonatomic, strong) NSDate *lastSeenAt;
- (instancetype)initWithSocketFD:(int)socketFD hello:(NSDictionary *)hello;
- (NSDictionary *)snapshot;
- (BOOL)sendCommand:(NSDictionary *)command error:(NSError **)error;
- (void)close;
@end

@implementation APTAgentSession {
    NSLock *_writeLock;
    BOOL _closed;
}

- (instancetype)initWithSocketFD:(int)socketFD hello:(NSDictionary *)hello {
    self = [super init];
    if (self) {
        _socketFD = socketFD;
        _identifier = NSUUID.UUID.UUIDString.lowercaseString;
        _status = [hello copy];
        _connectedAt = NSDate.date;
        _lastSeenAt = _connectedAt;
        _writeLock = [[NSLock alloc] init];
    }
    return self;
}

- (NSDictionary *)snapshot {
    @synchronized (self) {
        NSMutableDictionary *snapshot = [_status mutableCopy];
        snapshot[@"id"] = self.identifier;
        snapshot[@"connected"] = [NSNumber numberWithBool:!_closed];
        snapshot[@"connectedAt"] = @([self.connectedAt timeIntervalSince1970]);
        snapshot[@"lastSeenAt"] = @([self.lastSeenAt timeIntervalSince1970]);
        return snapshot;
    }
}

- (void)setStatus:(NSDictionary *)status {
    @synchronized (self) {
        _status = [status copy];
        _lastSeenAt = NSDate.date;
    }
}

- (BOOL)sendCommand:(NSDictionary *)command error:(NSError **)error {
    NSData *data = [NSJSONSerialization dataWithJSONObject:command options:0 error:error];
    if (!data || data.length > APTAgentMaximumPayload) return NO;
    APTAgentFrameHeader header = {
        .magic = htonl(APTAgentFrameMagic),
        .version = htons(APTAgentProtocolVersion),
        .type = htons(APTAgentMessageCommand),
        .payloadLength = htonl((uint32_t)data.length),
    };
    [_writeLock lock];
    BOOL success = !_closed && APTWriteAll(self.socketFD, &header, sizeof(header)) &&
                   APTWriteAll(self.socketFD, data.bytes, data.length);
    [_writeLock unlock];
    if (!success && error) *error = APTAgentError(2, @"Agent connection is unavailable");
    return success;
}

- (void)close {
    [_writeLock lock];
    BOOL shouldClose = NO;
    @synchronized (self) {
        if (!_closed) {
            _closed = YES;
            shouldClose = YES;
        }
    }
    if (shouldClose) {
        shutdown(self.socketFD, SHUT_RDWR);
        close(self.socketFD);
    }
    [_writeLock unlock];
}

@end

@interface APTAgentRegistry ()
@property(nonatomic, copy) NSString *socketPath;
@property(nonatomic, strong) NSMutableDictionary<NSString *, APTAgentSession *> *sessions;
@end

@implementation APTAgentRegistry

- (instancetype)initWithSocketPath:(NSString *)socketPath {
    self = [super init];
    if (self) {
        _socketPath = [socketPath copy];
        _sessions = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)run:(NSError **)error {
    NSString *directory = self.socketPath.stringByDeletingLastPathComponent;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                   withIntermediateDirectories:YES
                                                    attributes:@{NSFilePosixPermissions: @0755}
                                                         error:error]) return NO;
    unlink(self.socketPath.fileSystemRepresentation);

    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listener < 0) return NO;
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    if (strlcpy(address.sun_path, self.socketPath.fileSystemRepresentation,
                sizeof(address.sun_path)) >= sizeof(address.sun_path)) {
        close(listener);
        if (error) *error = APTAgentError(1, @"Agent socket path is too long");
        return NO;
    }
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(listener, 32) != 0) {
        close(listener);
        return NO;
    }
    const char *socketPath = self.socketPath.fileSystemRepresentation;
    struct passwd *mobile = getpwnam("mobile");
    if (mobile) chown(socketPath, mobile->pw_uid, mobile->pw_gid);
    chmod(socketPath, 0660);

    for (;;) {
        int client = accept(listener, NULL, NULL);
        if (client < 0) continue;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [self handleClient:client];
        });
    }
}

- (NSArray<NSDictionary *> *)agentSnapshots {
    @synchronized (self.sessions) {
        NSMutableArray *snapshots = [NSMutableArray arrayWithCapacity:self.sessions.count];
        for (APTAgentSession *session in self.sessions.allValues) [snapshots addObject:session.snapshot];
        [snapshots sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [(left[@"processName"] ?: @"") localizedCaseInsensitiveCompare:(right[@"processName"] ?: @"")];
        }];
        return snapshots;
    }
}

- (NSDictionary *)agentSnapshotWithIdentifier:(NSString *)identifier {
    @synchronized (self.sessions) {
        return self.sessions[identifier].snapshot;
    }
}

- (BOOL)sendCommand:(NSDictionary *)command
  toAgentWithIdentifier:(NSString *)identifier
                  error:(NSError **)error {
    APTAgentSession *session = nil;
    @synchronized (self.sessions) {
        session = self.sessions[identifier];
    }
    if (!session) {
        if (error) *error = APTAgentError(3, @"Agent not found");
        return NO;
    }
    return [session sendCommand:command error:error];
}

- (void)handleClient:(int)client {
    @autoreleasepool {
        APTAgentMessageType type = 0;
        NSDictionary *hello = APTReadJSONFrame(client, &type);
        if (!hello || type != APTAgentMessageHello) {
            close(client);
            return;
        }
        APTAgentSession *session = [[APTAgentSession alloc] initWithSocketFD:client hello:hello];
        @synchronized (self.sessions) {
            self.sessions[session.identifier] = session;
        }
        NSLog(@"AppleTrace agent connected [%@]: %@", session.identifier, hello);

        NSString *testCommands = NSProcessInfo.processInfo.environment[@"APPLETRACE_TEST_COMMANDS"];
        if (testCommands.length) {
            for (NSString *name in [testCommands componentsSeparatedByString:@","]) {
                NSDictionary *command = [name isEqualToString:@"filters"]
                    ? @{@"command": name, @"allowClassPrefixes": @[@"APTAllowed"], @"denyClassPrefixes": @[@"APTDeny"]}
                    : @{@"command": name};
                [session sendCommand:command error:nil];
            }
        }

        for (;;) {
            NSDictionary *payload = APTReadJSONFrame(client, &type);
            if (!payload) break;
            if (type == APTAgentMessageStatus || type == APTAgentMessageHeartbeat) {
                session.status = payload;
                NSLog(@"AppleTrace agent status [%@]: %@", session.identifier, payload);
            }
        }

        @synchronized (self.sessions) {
            [self.sessions removeObjectForKey:session.identifier];
        }
        [session close];
        NSLog(@"AppleTrace agent disconnected [%@]", session.identifier);
    }
}

@end
