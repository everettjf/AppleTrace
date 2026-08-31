#import "ControlServer.h"
#import "AgentRegistry.h"

#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>

static const NSUInteger APTHTTPMaximumRequest = 1024 * 1024;

static BOOL APTHTTPWriteAll(int socketFD, const void *bytes, size_t length) {
    const uint8_t *cursor = bytes;
    while (length > 0) {
        ssize_t written = write(socketFD, cursor, length);
        if (written <= 0) return NO;
        cursor += written;
        length -= (size_t)written;
    }
    return YES;
}

static NSString *APTHTTPReason(NSInteger status) {
    switch (status) {
        case 200: return @"OK";
        case 202: return @"Accepted";
        case 400: return @"Bad Request";
        case 401: return @"Unauthorized";
        case 404: return @"Not Found";
        case 405: return @"Method Not Allowed";
        default: return @"Internal Server Error";
    }
}

static NSString *APTContentType(NSString *path) {
    NSString *extension = path.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"html"]) return @"text/html; charset=utf-8";
    if ([extension isEqualToString:@"css"]) return @"text/css; charset=utf-8";
    if ([extension isEqualToString:@"js"]) return @"text/javascript; charset=utf-8";
    if ([extension isEqualToString:@"svg"]) return @"image/svg+xml";
    return @"application/octet-stream";
}

@interface APTControlServer ()
@property(nonatomic, strong) APTAgentRegistry *registry;
@property(nonatomic) uint16_t port;
@property(nonatomic, copy) NSString *token;
@property(nonatomic, copy) NSString *consolePath;
@end

@implementation APTControlServer

- (instancetype)initWithRegistry:(APTAgentRegistry *)registry
                             port:(uint16_t)port
                            token:(NSString *)token
                      consolePath:(NSString *)consolePath {
    self = [super init];
    if (self) {
        _registry = registry;
        _port = port;
        _token = [token copy];
        _consolePath = [consolePath copy];
    }
    return self;
}

- (BOOL)run:(NSError **)error {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) return NO;
    int reuse = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    struct sockaddr_in address = {0};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(self.port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(listener, 32) != 0) {
        close(listener);
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    NSLog(@"appletraced control server listening on http://127.0.0.1:%u", self.port);
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
        NSMutableData *requestData = [NSMutableData data];
        NSRange separator = NSMakeRange(NSNotFound, 0);
        NSUInteger expectedLength = NSNotFound;
        uint8_t buffer[8192];
        while (requestData.length < APTHTTPMaximumRequest) {
            ssize_t count = read(client, buffer, sizeof(buffer));
            if (count <= 0) break;
            [requestData appendBytes:buffer length:(NSUInteger)count];
            separator = [requestData rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]
                                         options:0
                                           range:NSMakeRange(0, requestData.length)];
            if (separator.location != NSNotFound) {
                NSString *head = [[NSString alloc] initWithData:[requestData subdataWithRange:NSMakeRange(0, separator.location)]
                                                       encoding:NSUTF8StringEncoding];
                NSUInteger contentLength = 0;
                for (NSString *line in [head componentsSeparatedByString:@"\r\n"]) {
                    if ([[line lowercaseString] hasPrefix:@"content-length:"]) {
                        contentLength = [[[line componentsSeparatedByString:@":"] lastObject]
                            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].integerValue;
                    }
                }
                expectedLength = NSMaxRange(separator) + contentLength;
                if (requestData.length >= expectedLength) break;
            }
        }
        if (separator.location == NSNotFound || expectedLength == NSNotFound || requestData.length < expectedLength) {
            [self sendJSON:@{@"error": @"malformed request"} status:400 toClient:client];
            close(client);
            return;
        }

        NSString *head = [[NSString alloc] initWithData:[requestData subdataWithRange:NSMakeRange(0, separator.location)]
                                               encoding:NSUTF8StringEncoding];
        NSArray<NSString *> *lines = [head componentsSeparatedByString:@"\r\n"];
        NSArray<NSString *> *requestLine = [lines.firstObject componentsSeparatedByString:@" "];
        if (requestLine.count < 2) {
            [self sendJSON:@{@"error": @"malformed request"} status:400 toClient:client];
            close(client);
            return;
        }
        NSString *method = requestLine[0];
        NSString *path = [requestLine[1] componentsSeparatedByString:@"?"][0];
        NSMutableDictionary *headers = [NSMutableDictionary dictionary];
        for (NSString *line in [lines subarrayWithRange:NSMakeRange(1, lines.count - 1)]) {
            NSRange colon = [line rangeOfString:@":"];
            if (colon.location == NSNotFound) continue;
            NSString *key = [[line substringToIndex:colon.location] lowercaseString];
            headers[key] = [[line substringFromIndex:NSMaxRange(colon)]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        }
        NSData *body = [requestData subdataWithRange:NSMakeRange(NSMaxRange(separator), expectedLength - NSMaxRange(separator))];

        if ([path isEqualToString:@"/"] || [path hasPrefix:@"/assets/"]) {
            [self sendAsset:path toClient:client];
        } else if (![self authorized:headers]) {
            [self sendJSON:@{@"error": @"unauthorized"} status:401 toClient:client];
        } else {
            [self routeMethod:method path:path body:body toClient:client];
        }
        close(client);
    }
}

- (BOOL)authorized:(NSDictionary *)headers {
    return [headers[@"authorization"] isEqualToString:[@"Bearer " stringByAppendingString:self.token]] ||
           [headers[@"x-appletrace-token"] isEqualToString:self.token];
}

- (void)routeMethod:(NSString *)method path:(NSString *)path body:(NSData *)body toClient:(int)client {
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/api/v1/agents"]) {
        [self sendJSON:@{@"protocolVersion": @1, @"agents": self.registry.agentSnapshots}
                 status:200 toClient:client];
        return;
    }
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    if (parts.count < 5 || ![parts[1] isEqualToString:@"api"] || ![parts[2] isEqualToString:@"v1"] ||
        ![parts[3] isEqualToString:@"agents"]) {
        [self sendJSON:@{@"error": @"not found"} status:404 toClient:client];
        return;
    }
    NSString *identifier = [parts[4] stringByRemovingPercentEncoding];
    if ([method isEqualToString:@"GET"] && parts.count == 5) {
        NSDictionary *snapshot = [self.registry agentSnapshotWithIdentifier:identifier];
        [self sendJSON:snapshot ?: @{@"error": @"agent not found"} status:snapshot ? 200 : 404 toClient:client];
        return;
    }
    if ([method isEqualToString:@"GET"] && parts.count >= 6 && [parts[5] isEqualToString:@"artifacts"]) {
        if (parts.count == 6) {
            [self sendArtifactsForAgent:identifier toClient:client];
        } else if (parts.count == 7) {
            [self sendArtifact:[parts[6] stringByRemovingPercentEncoding]
                      forAgent:identifier
                      toClient:client];
        } else {
            [self sendJSON:@{@"error": @"not found"} status:404 toClient:client];
        }
        return;
    }
    if (![method isEqualToString:@"POST"] || parts.count < 6) {
        [self sendJSON:@{@"error": @"method not allowed"} status:405 toClient:client];
        return;
    }
    NSString *action = parts[5];
    NSMutableDictionary *command = [@{@"command": action} mutableCopy];
    if ([action isEqualToString:@"filters"]) {
        id filters = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        if (![filters isKindOfClass:NSDictionary.class]) {
            [self sendJSON:@{@"error": @"invalid filters"} status:400 toClient:client];
            return;
        }
        command[@"allowClassPrefixes"] = filters[@"allowClassPrefixes"] ?: @[];
        command[@"denyClassPrefixes"] = filters[@"denyClassPrefixes"] ?: @[];
    } else if (![@[@"start", @"stop", @"flush"] containsObject:action]) {
        [self sendJSON:@{@"error": @"unknown command"} status:404 toClient:client];
        return;
    }
    NSError *error = nil;
    BOOL sent = [self.registry sendCommand:command toAgentWithIdentifier:identifier error:&error];
    [self sendJSON:sent ? @{@"accepted": @YES, @"agentId": identifier}
                        : @{@"error": error.localizedDescription ?: @"command failed"}
             status:sent ? 202 : 404 toClient:client];
}

- (NSString *)traceDirectoryForAgent:(NSString *)identifier {
    NSString *directory = [self.registry agentSnapshotWithIdentifier:identifier][@"traceDirectory"];
    return [directory isKindOfClass:NSString.class] ? directory.stringByStandardizingPath : nil;
}

- (void)sendArtifactsForAgent:(NSString *)identifier toClient:(int)client {
    NSString *directory = [self traceDirectoryForAgent:identifier];
    if (!directory) {
        [self sendJSON:@{@"error": @"agent not found"} status:404 toClient:client];
        return;
    }
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] ?: @[];
    NSMutableArray *artifacts = [NSMutableArray array];
    for (NSString *name in names) {
        if (![@[@"appletrace", @"appletracebin"] containsObject:name.pathExtension.lowercaseString]) continue;
        NSString *file = [directory stringByAppendingPathComponent:name];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:file error:nil];
        if (![attributes.fileType isEqualToString:NSFileTypeRegular]) continue;
        [artifacts addObject:@{
            @"name": name,
            @"size": attributes[NSFileSize] ?: @0,
            @"modifiedAt": @([attributes[NSFileModificationDate] timeIntervalSince1970]),
        }];
    }
    [artifacts sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [right[@"modifiedAt"] compare:left[@"modifiedAt"]];
    }];
    [self sendJSON:artifacts status:200 toClient:client];
}

- (void)sendArtifact:(NSString *)name forAgent:(NSString *)identifier toClient:(int)client {
    NSString *directory = [self traceDirectoryForAgent:identifier];
    if (!directory || !name.length || ![name isEqualToString:name.lastPathComponent] ||
        ![@[@"appletrace", @"appletracebin"] containsObject:name.pathExtension.lowercaseString]) {
        [self sendJSON:@{@"error": @"invalid artifact"} status:400 toClient:client];
        return;
    }
    NSString *file = [[directory stringByAppendingPathComponent:name] stringByStandardizingPath];
    if (![[file stringByDeletingLastPathComponent] isEqualToString:directory]) {
        [self sendJSON:@{@"error": @"invalid artifact"} status:400 toClient:client];
        return;
    }
    NSData *body = [NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:nil];
    if (!body) {
        [self sendJSON:@{@"error": @"artifact not found"} status:404 toClient:client];
        return;
    }
    [self sendBody:body contentType:@"application/octet-stream" status:200 toClient:client];
}

- (void)sendJSON:(id)value status:(NSInteger)status toClient:(int)client {
    NSData *body = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil] ?: [NSData data];
    [self sendBody:body contentType:@"application/json; charset=utf-8" status:status toClient:client];
}

- (void)sendAsset:(NSString *)path toClient:(int)client {
    NSString *relative = [path isEqualToString:@"/"] ? @"index.html" : [path substringFromIndex:1];
    if ([relative containsString:@".."] || [relative hasPrefix:@"/"]) {
        [self sendJSON:@{@"error": @"invalid asset path"} status:400 toClient:client];
        return;
    }
    NSString *root = self.consolePath.stringByStandardizingPath;
    NSString *file = [[root stringByAppendingPathComponent:relative] stringByStandardizingPath];
    if (![[file stringByDeletingLastPathComponent] hasPrefix:root]) {
        [self sendJSON:@{@"error": @"invalid asset path"} status:400 toClient:client];
        return;
    }
    NSData *body = [NSData dataWithContentsOfFile:file];
    if (!body) {
        [self sendJSON:@{@"error": @"asset not found"} status:404 toClient:client];
        return;
    }
    [self sendBody:body contentType:APTContentType(file) status:200 toClient:client];
}

- (void)sendBody:(NSData *)body contentType:(NSString *)contentType status:(NSInteger)status toClient:(int)client {
    NSString *head = [NSString stringWithFormat:
        @"HTTP/1.1 %ld %@\r\nContent-Type: %@\r\nContent-Length: %lu\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n",
        (long)status, APTHTTPReason(status), contentType, (unsigned long)body.length];
    NSData *headData = [head dataUsingEncoding:NSUTF8StringEncoding];
    APTHTTPWriteAll(client, headData.bytes, headData.length);
    APTHTTPWriteAll(client, body.bytes, body.length);
}

@end
