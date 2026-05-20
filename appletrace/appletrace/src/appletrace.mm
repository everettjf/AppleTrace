//
//  appletrace.mm
//  appletrace
//

#import "appletrace.h"

#include <atomic>
#include <string>

#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>

namespace {

constexpr size_t kDefaultBlockSize = 16 * 1024 * 1024;
constexpr size_t kMinimumBlockSize = 1 * 1024 * 1024;
constexpr size_t kMaximumBlockSize = 256 * 1024 * 1024;

bool BoolFromEnvironment(NSString *key, bool fallback) {
    NSString *value = [[[NSProcessInfo processInfo] environment] objectForKey:key];
    if (!value.length) {
        return fallback;
    }

    NSString *normalized = value.lowercaseString;
    return ![normalized isEqualToString:@"0"] &&
           ![normalized isEqualToString:@"false"] &&
           ![normalized isEqualToString:@"no"];
}

size_t BlockSizeFromEnvironment() {
    NSString *value = [[[NSProcessInfo processInfo] environment] objectForKey:@"APPLETRACE_BLOCK_SIZE_MB"];
    if (!value.length) {
        return kDefaultBlockSize;
    }

    NSInteger megabytes = value.integerValue;
    if (megabytes <= 0) {
        return kDefaultBlockSize;
    }

    size_t bytes = static_cast<size_t>(megabytes) * 1024 * 1024;
    if (bytes < kMinimumBlockSize) {
        return kMinimumBlockSize;
    }
    if (bytes > kMaximumBlockSize) {
        return kMaximumBlockSize;
    }
    return bytes;
}

std::string EscapeJSONString(const char *input) {
    if (!input) {
        return "";
    }

    std::string escaped;
    for (const unsigned char *cursor = reinterpret_cast<const unsigned char *>(input); *cursor; ++cursor) {
        switch (*cursor) {
            case '\\':
                escaped += "\\\\";
                break;
            case '"':
                escaped += "\\\"";
                break;
            case '\b':
                escaped += "\\b";
                break;
            case '\f':
                escaped += "\\f";
                break;
            case '\n':
                escaped += "\\n";
                break;
            case '\r':
                escaped += "\\r";
                break;
            case '\t':
                escaped += "\\t";
                break;
            default:
                if (*cursor < 0x20) {
                    char buffer[7] = {0};
                    snprintf(buffer, sizeof(buffer), "\\u%04x", *cursor);
                    escaped += buffer;
                } else {
                    escaped.push_back(static_cast<char>(*cursor));
                }
                break;
        }
    }
    return escaped;
}

}  // namespace

namespace appletrace {

class Logger {
public:
    explicit Logger(size_t block_size) : block_size_(block_size) {}
    ~Logger() { Close(); }

    bool Open(const char *log_path) {
        Close();

        ::remove(log_path);
        fd_ = ::open(log_path, O_CREAT | O_RDWR, static_cast<mode_t>(0600));
        if (fd_ < 0) {
            NSLog(@"AppleTrace: failed to open log file %s", log_path);
            return false;
        }

        if (::ftruncate(fd_, static_cast<off_t>(block_size_)) != 0) {
            NSLog(@"AppleTrace: failed to size log file %s", log_path);
            Close();
            return false;
        }

        file_start_ = static_cast<char *>(::mmap(nullptr, block_size_, PROT_READ | PROT_WRITE, MAP_SHARED, fd_, 0));
        if (file_start_ == MAP_FAILED) {
            file_start_ = nullptr;
            NSLog(@"AppleTrace: failed to map log file %s", log_path);
            Close();
            return false;
        }

        file_cur_ = file_start_;
        cur_size_ = 0;
        return true;
    }

    void Close() {
        Flush();

        if (file_start_) {
            ::munmap(file_start_, block_size_);
        }
        if (fd_ >= 0) {
            ::ftruncate(fd_, static_cast<off_t>(cur_size_));
            ::close(fd_);
        }

        fd_ = -1;
        file_start_ = nullptr;
        file_cur_ = nullptr;
        cur_size_ = 0;
    }

    void Flush() {
        if (!file_start_ || fd_ < 0) {
            return;
        }
        if (cur_size_ > 0) {
            ::msync(file_start_, cur_size_, MS_SYNC);
        }
        ::fsync(fd_);
    }

    bool AddLine(const std::string &line) {
        if (!file_cur_) {
            return false;
        }

        const size_t required = line.size() + 1;
        if (cur_size_ + required > block_size_) {
            return false;
        }

        memcpy(file_cur_, line.data(), line.size());
        file_cur_ += line.size();
        *file_cur_++ = '\n';
        cur_size_ += required;
        return true;
    }

private:
    size_t block_size_;
    int fd_ = -1;
    char *file_start_ = nullptr;
    char *file_cur_ = nullptr;
    size_t cur_size_ = 0;
};

class LoggerManager {
public:
    LoggerManager() : log_(BlockSizeFromEnvironment()) {}

    bool Open() {
        std::string path = GetFilePath();
        if (!log_.Open(path.c_str())) {
            return false;
        }
        ++file_counter_;
        return true;
    }

    void Flush() {
        log_.Flush();
    }

    void AddLine(const std::string &line) {
        if (log_.AddLine(line)) {
            return;
        }

        NSLog(@"AppleTrace: rolling trace fragment");
        if (!Open()) {
            return;
        }

        if (!log_.AddLine(line)) {
            NSLog(@"AppleTrace: failed to write event after rollover");
        }
    }

    static NSString *CurrentDirectory() {
        InitializeWorkDirectory();
        return work_dir_;
    }

private:
    static void InitializeWorkDirectory() {
        static dispatch_once_t once_token;
        dispatch_once(&once_token, ^{
            NSString *configured = [[[NSProcessInfo processInfo] environment] objectForKey:@"APPLETRACE_DATA_DIR"];
            NSString *root_dir = configured.length
                                     ? configured.stringByStandardizingPath
                                     : [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES)[0]
                                           stringByAppendingPathComponent:@"appletracedata"];

            NSFileManager *file_manager = [NSFileManager defaultManager];
            BOOL keep_existing = BoolFromEnvironment(@"APPLETRACE_KEEP_EXISTING", false);
            work_dir_ = root_dir;

            if (keep_existing) {
                NSInteger sequence = 1;
                while ([file_manager fileExistsAtPath:work_dir_]) {
                    NSString *name = [NSString stringWithFormat:@"%@_%ld", root_dir.lastPathComponent, (long)sequence];
                    work_dir_ = [root_dir.stringByDeletingLastPathComponent stringByAppendingPathComponent:name];
                    sequence += 1;
                }
            } else {
                [file_manager removeItemAtPath:work_dir_ error:nil];
            }

            NSError *error = nil;
            [file_manager createDirectoryAtPath:work_dir_ withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                NSLog(@"AppleTrace: failed to create trace directory %@: %@", work_dir_, error);
            }
        });
    }

    std::string GetFilePath() {
        InitializeWorkDirectory();

        int file_index = file_counter_.load();
        NSString *log_name = file_index == 0
                                 ? @"trace.appletrace"
                                 : [NSString stringWithFormat:@"trace_%d.appletrace", file_index];
        NSString *log_path = [work_dir_ stringByAppendingPathComponent:log_name];
        NSLog(@"AppleTrace: log path = %@", log_path);
        return std::string(log_path.UTF8String);
    }

    static std::atomic<int> file_counter_;
    static NSString *work_dir_;
    Logger log_;
};

std::atomic<int> LoggerManager::file_counter_{0};
NSString *LoggerManager::work_dir_ = nil;

class Trace {
public:
    bool Open() {
        static dispatch_once_t once_token;
        dispatch_once(&once_token, ^{
            enabled_.store(BoolFromEnvironment(@"APPLETRACE_ENABLED", true));
            if (!log_.Open()) {
                return;
            }

            queue_ = dispatch_queue_create("appletrace.queue", DISPATCH_QUEUE_SERIAL);
            mach_timebase_info(&timeinfo_);
            begin_ = CurrentTimeNs();
            pid_ = getpid();

            dispatch_sync(queue_, ^{
                WriteMetadataLocked();
                log_.Flush();
            });
        });

        return queue_ != nullptr;
    }

    void SetEnabled(bool enabled) {
        enabled_.store(enabled);
    }

    bool IsEnabled() const {
        return enabled_.load();
    }

    const char *GetTraceDirectory() const {
        return LoggerManager::CurrentDirectory().UTF8String;
    }

    void WriteSection(const char *name, const char *phase) {
        if (!IsEnabled() || !name || name[0] == '\0' || !queue_) {
            return;
        }

        const uint64_t thread_id = ResolveThreadId();
        const uint64_t elapsed_us = (CurrentTimeNs() - begin_) / 1000;
        std::string line = BuildEventLine(name, phase, thread_id, elapsed_us);
        dispatch_async(queue_, ^{
            log_.AddLine(line);
        });
    }

    void WriteInstant(const char *name) {
        if (!IsEnabled() || !name || name[0] == '\0' || !queue_) {
            return;
        }

        const uint64_t thread_id = ResolveThreadId();
        const uint64_t elapsed_us = (CurrentTimeNs() - begin_) / 1000;
        std::string line =
            "{\"name\":\"" + EscapeJSONString(name) +
            "\",\"cat\":\"appletrace\",\"ph\":\"i\",\"pid\":" + std::to_string(pid_) +
            ",\"tid\":" + std::to_string(thread_id) + ",\"ts\":" + std::to_string(elapsed_us) +
            ",\"s\":\"t\"}";
        dispatch_async(queue_, ^{
            log_.AddLine(line);
        });
    }

    void WriteCounter(const char *name, double value) {
        if (!IsEnabled() || !name || name[0] == '\0' || !queue_) {
            return;
        }

        const uint64_t thread_id = ResolveThreadId();
        const uint64_t elapsed_us = (CurrentTimeNs() - begin_) / 1000;
        char value_buffer[64] = {0};
        snprintf(value_buffer, sizeof(value_buffer), "%g", value);
        std::string line =
            "{\"name\":\"" + EscapeJSONString(name) +
            "\",\"cat\":\"appletrace\",\"ph\":\"C\",\"pid\":" + std::to_string(pid_) +
            ",\"tid\":" + std::to_string(thread_id) + ",\"ts\":" + std::to_string(elapsed_us) +
            ",\"args\":{\"value\":" + value_buffer + "}}";
        dispatch_async(queue_, ^{
            log_.AddLine(line);
        });
    }

    // Nestable async events ("b"/"e"): used to track work that flows across
    // threads or dispatch queues, matched by (name, async_id).
    void WriteAsync(const char *name, const char *phase, uint64_t async_id) {
        if (!IsEnabled() || !name || name[0] == '\0' || !queue_) {
            return;
        }

        const uint64_t thread_id = ResolveThreadId();
        const uint64_t elapsed_us = (CurrentTimeNs() - begin_) / 1000;
        std::string line =
            "{\"name\":\"" + EscapeJSONString(name) +
            "\",\"cat\":\"appletrace\",\"ph\":\"" + phase + "\",\"id\":" + std::to_string(async_id) +
            ",\"pid\":" + std::to_string(pid_) + ",\"tid\":" + std::to_string(thread_id) +
            ",\"ts\":" + std::to_string(elapsed_us) + "}";
        dispatch_async(queue_, ^{
            log_.AddLine(line);
        });
    }

    void Flush() {
        if (!queue_) {
            return;
        }
        dispatch_sync(queue_, ^{
            log_.Flush();
        });
    }

    void SyncWait() {
        Flush();
    }

private:
    uint64_t CurrentTimeNs() const {
        const uint64_t now = mach_absolute_time();
        return now * timeinfo_.numer / timeinfo_.denom;
    }

    uint64_t ResolveThreadId() {
        uint64_t thread_id = 0;
        pthread_threadid_np(pthread_self(), &thread_id);
        if (main_thread_id_.load() == 0 && pthread_main_np() != 0) {
            uint64_t expected = 0;
            main_thread_id_.compare_exchange_strong(expected, thread_id);
        }
        const uint64_t reported = (thread_id == main_thread_id_.load()) ? 0 : thread_id;
        EmitThreadNameOnce(reported);
        return reported;
    }

    void EmitThreadNameOnce(uint64_t reported_thread_id) {
        static __thread bool named = false;
        if (named || !queue_) {
            return;
        }
        named = true;

        std::string thread_name;
        if (reported_thread_id == 0) {
            thread_name = "Main Thread";
        } else {
            char buffer[256] = {0};
            if (pthread_getname_np(pthread_self(), buffer, sizeof(buffer)) == 0 && buffer[0] != '\0') {
                thread_name = buffer;
            } else {
                thread_name = "Thread " + std::to_string(reported_thread_id);
            }
        }

        std::string line =
            "{\"name\":\"thread_name\",\"ph\":\"M\",\"pid\":" + std::to_string(pid_) +
            ",\"tid\":" + std::to_string(reported_thread_id) + ",\"args\":{\"name\":\"" +
            EscapeJSONString(thread_name.c_str()) + "\"}}";
        dispatch_async(queue_, ^{
            log_.AddLine(line);
        });
    }

    std::string BuildEventLine(const char *name, const char *phase, uint64_t thread_id, uint64_t elapsed_us) const {
        std::string escaped_name = EscapeJSONString(name);
        std::string escaped_phase = EscapeJSONString(phase);
        return "{\"name\":\"" + escaped_name + "\",\"cat\":\"appletrace\",\"ph\":\"" + escaped_phase +
               "\",\"pid\":" + std::to_string(pid_) + ",\"tid\":" + std::to_string(thread_id) +
               ",\"ts\":" + std::to_string(elapsed_us) + "}";
    }

    void WriteMetadataLocked() {
        NSString *process_name = [[NSProcessInfo processInfo] processName];
        std::string line =
            "{\"name\":\"process_name\",\"ph\":\"M\",\"pid\":" + std::to_string(pid_) +
            ",\"tid\":0,\"args\":{\"name\":\"" + EscapeJSONString(process_name.UTF8String) + "\"}}";
        log_.AddLine(line);
    }

    LoggerManager log_;
    dispatch_queue_t queue_ = nullptr;
    uint64_t begin_ = 0;
    mach_timebase_info_data_t timeinfo_ = {};
    pid_t pid_ = 0;
    std::atomic<uint64_t> main_thread_id_{0};
    std::atomic<bool> enabled_{true};
};

class TraceManager {
public:
    static TraceManager &Instance() {
        static TraceManager manager;
        return manager;
    }

    void BeginSection(const char *name) {
        trace_.WriteSection(name, "B");
    }

    void EndSection(const char *name) {
        trace_.WriteSection(name, "E");
    }

    void Instant(const char *name) {
        trace_.WriteInstant(name);
    }

    void Counter(const char *name, double value) {
        trace_.WriteCounter(name, value);
    }

    void AsyncBegin(const char *name, uint64_t async_id) {
        trace_.WriteAsync(name, "b", async_id);
    }

    void AsyncEnd(const char *name, uint64_t async_id) {
        trace_.WriteAsync(name, "e", async_id);
    }

    void Flush() {
        trace_.Flush();
    }

    void SyncWait() {
        trace_.SyncWait();
    }

    void SetEnabled(bool enabled) {
        trace_.SetEnabled(enabled);
    }

    bool IsEnabled() const {
        return trace_.IsEnabled();
    }

    const char *GetTraceDirectory() const {
        return trace_.GetTraceDirectory();
    }

private:
    TraceManager() {
        if (!trace_.Open()) {
            NSLog(@"AppleTrace: failed to initialize trace runtime");
        }
    }

    Trace trace_;
};

}  // namespace appletrace

void APTBeginSection(const char *name) {
    appletrace::TraceManager::Instance().BeginSection(name);
}

void APTEndSection(const char *name) {
    appletrace::TraceManager::Instance().EndSection(name);
}

void APTInstant(const char *name) {
    appletrace::TraceManager::Instance().Instant(name);
}

void APTCounter(const char *name, double value) {
    appletrace::TraceManager::Instance().Counter(name, value);
}

void APTAsyncBegin(const char *name, uint64_t async_id) {
    appletrace::TraceManager::Instance().AsyncBegin(name, async_id);
}

void APTAsyncEnd(const char *name, uint64_t async_id) {
    appletrace::TraceManager::Instance().AsyncEnd(name, async_id);
}

void APTSyncWait() {
    appletrace::TraceManager::Instance().SyncWait();
}

void APTFlush() {
    appletrace::TraceManager::Instance().Flush();
}

void APTSetEnabled(BOOL enabled) {
    appletrace::TraceManager::Instance().SetEnabled(enabled);
}

BOOL APTIsEnabled() {
    return appletrace::TraceManager::Instance().IsEnabled();
}

const char *APTGetTraceDirectory() {
    return appletrace::TraceManager::Instance().GetTraceDirectory();
}

@interface APTInterface : NSObject
@end

@implementation APTInterface

+ (void)syncWait {
    APTSyncWait();
}

@end
