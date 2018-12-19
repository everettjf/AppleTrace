#line 1 "/Users/everettjf/github/AppleTrace/loader/AppleTraceLoader/AppleTraceLoader.xm"


#if TARGET_OS_SIMULATOR
#error Do not support the simulator, please use the real iPhone Device.
#endif

#import <UIKit/UIKit.h>
#include <dlfcn.h>
static __attribute__((constructor)) void _logosLocalCtor_344ae32b(int __unused argc, char __unused **argv, char __unused **envp) {
    @autoreleasepool{
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.everettjf.AppleTraceLoader.plist"];



NSString *libraryPath = @"/usr/lib/TweakInject/appletrace.framework/appletrace";

        if([[prefs objectForKey:[NSString stringWithFormat:@"AppleTraceEnabled-%@", [[NSBundle mainBundle] bundleIdentifier]]] boolValue]) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:libraryPath]){
                void * ret = dlopen([libraryPath UTF8String], RTLD_NOW);
                if(ret == 0){
                    const char * errinfo = dlerror();
                    NSLog(@"AppleTraceLoader load failed : %@",[NSString stringWithUTF8String: errinfo]);
                }else{
                    NSLog(@"AppleTraceLoader loaded %@", libraryPath);
                }
            }else{
                NSLog(@"appletrace.framework not found");
            }
        }
    }
}
