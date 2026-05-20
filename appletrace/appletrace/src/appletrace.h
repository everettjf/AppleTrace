//
//  appletrace.h
//  appletrace
//

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT void APTBeginSection(const char *name);
FOUNDATION_EXPORT void APTEndSection(const char *name);
FOUNDATION_EXPORT void APTInstant(const char *name);
FOUNDATION_EXPORT void APTCounter(const char *name, double value);
FOUNDATION_EXPORT void APTSyncWait(void);
FOUNDATION_EXPORT void APTFlush(void);
FOUNDATION_EXPORT void APTSetEnabled(BOOL enabled);
FOUNDATION_EXPORT BOOL APTIsEnabled(void);
FOUNDATION_EXPORT const char *APTGetTraceDirectory(void);
FOUNDATION_EXPORT BOOL APTInstallObjcMsgSendHook(void);
FOUNDATION_EXPORT BOOL APTIsObjcMsgSendHookInstalled(void);

#ifdef __OBJC__
#define APTCurrentSectionName [NSString stringWithFormat:@"[%@ %@]", NSStringFromClass([self class]), NSStringFromSelector(_cmd)].UTF8String
#define APTBegin APTBeginSection(APTCurrentSectionName)
#define APTEnd APTEndSection(APTCurrentSectionName)
#endif

#ifdef __cplusplus
namespace appletrace {
class ScopedSection {
public:
    explicit ScopedSection(const char *name) : name_(name) {
        APTBeginSection(name_);
    }

    ~ScopedSection() {
        APTEndSection(name_);
    }

private:
    const char *name_;
};
}  // namespace appletrace

#define APT_SCOPE_SECTION_IMPL(name, line) appletrace::ScopedSection __apt_scoped_section_##line(name)
#define APTScopeSection(name) APT_SCOPE_SECTION_IMPL(name, __LINE__)
#endif
