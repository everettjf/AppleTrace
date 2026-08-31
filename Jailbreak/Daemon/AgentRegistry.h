#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface APTAgentRegistry : NSObject
- (instancetype)initWithSocketPath:(NSString *)socketPath;
- (BOOL)run:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
