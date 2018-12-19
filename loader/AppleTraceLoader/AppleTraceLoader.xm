// See http://iphonedevwiki.net/index.php/Logos

#if TARGET_OS_SIMULATOR
#error Do not support the simulator, please use the real iPhone Device.
#endif


#include <dlfcn.h>
%ctor {
    @autoreleasepool{
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.everettjf.AppleTraceLoader.plist"];

        NSString *libraryPath;
        if([UIDevice currentDevice].systemVersion.integerValue >= 11){
            // iOS 11
            libraryPath = @"/usr/lib/TweakInject/appletrace.framework/appletrace";
        } else {
            // iOS 10
            libraryPath = @"/Library/Frameworks/appletrace.framework/appletrace";
        }

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
