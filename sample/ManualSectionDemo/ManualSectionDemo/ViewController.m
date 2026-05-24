//
//  ViewController.m
//  ManualSectionDemo
//
//  Created by everettjf on 21/09/2017.
//  Copyright © 2017 everettjf. All rights reserved.
//
//  This view controller is the whole demo: tap "Generate Trace" to run a
//  curated, multi-threaded workload that emits a rich AppleTrace timeline
//  (nested sections, named worker threads, async flows, counters, instants),
//  then follow the on-screen steps to merge and open it in Perfetto.

#import "ViewController.h"
#import "appletrace.h"

#import <TargetConditionals.h>
#import <pthread.h>
#import <stdatomic.h>
#import <unistd.h>

#pragma mark - Trace workload

// Thin wrappers that also count how many trace events the showcase emitted so
// the UI can report a number. Counting is atomic because the workload runs
// across several threads at once.
static atomic_uint gShowcaseEvents;

static inline void TBegin(const char *name) { APTBeginSection(name); atomic_fetch_add(&gShowcaseEvents, 1); }
static inline void TEnd(const char *name)   { APTEndSection(name);   atomic_fetch_add(&gShowcaseEvents, 1); }
static inline void TInstant(const char *name) { APTInstant(name);    atomic_fetch_add(&gShowcaseEvents, 1); }
static inline void TCounter(const char *name, double v) { APTCounter(name, v); atomic_fetch_add(&gShowcaseEvents, 1); }
static inline void TAsyncBegin(const char *name, uint64_t i) { APTAsyncBegin(name, i); atomic_fetch_add(&gShowcaseEvents, 1); }
static inline void TAsyncEnd(const char *name, uint64_t i)   { APTAsyncEnd(name, i);   atomic_fetch_add(&gShowcaseEvents, 1); }
static inline void TSleepMs(double ms) { usleep((useconds_t)(ms * 1000.0)); }

static void *APTThreadTrampoline(void *ctx) {
    void (^block)(void) = (__bridge_transfer void (^)(void))ctx;
    block();
    return NULL;
}

// Spawns a named pthread running `block`. The name shows up as the track name
// in Perfetto, which is what makes the timeline readable.
static pthread_t APTSpawnNamed(void (^block)(void)) {
    pthread_t thread = NULL;
    pthread_create(&thread, NULL, APTThreadTrampoline, (__bridge_retained void *)[block copy]);
    return thread;
}

// Runs the whole showcase and flushes. Returns the number of events emitted.
static NSUInteger APTGenerateShowcase(void) {
    atomic_store(&gShowcaseEvents, 0);
    pthread_setname_np("Showcase");

    TInstant("scenario_start");

    // Phase 1 — a believable app startup on the coordinator thread.
    TBegin("App Launch");
    {
        TBegin("Load Configuration");
        TSleepMs(8);
        TCounter("Config Keys", 142);
        TEnd("Load Configuration");

        TBegin("Build View Hierarchy");
        {
            TBegin("Inflate Storyboard"); TSleepMs(6); TEnd("Inflate Storyboard");
            TBegin("Apply Theme");        TSleepMs(4); TEnd("Apply Theme");
        }
        TEnd("Build View Hierarchy");

        TBegin("Warm Image Cache"); TSleepMs(5); TEnd("Warm Image Cache");
    }
    TEnd("App Launch");
    TInstant("first_frame_ready");

    // Phase 2 — three named workers run in parallel, so Perfetto shows three
    // separate tracks with overlapping slices plus async download arcs.
    pthread_t imageThread = APTSpawnNamed(^{
        pthread_setname_np("ImageDecoder");
        for (int i = 1; i <= 8; i++) {
            char name[64];
            snprintf(name, sizeof(name), "Decode image #%d", i);
            TBegin(name);
            {
                TBegin("Read bytes"); TSleepMs(2 + (i % 3)); TEnd("Read bytes");
                TBegin("Resize");     TSleepMs(3);           TEnd("Resize");
            }
            TEnd(name);
            TCounter("Images Decoded", i);
        }
    });

    pthread_t networkThread = APTSpawnNamed(^{
        pthread_setname_np("NetworkClient");
        TAsyncBegin("GET /feed.json", 1001);
        {
            TBegin("TLS Handshake"); TSleepMs(10); TEnd("TLS Handshake");

            TAsyncBegin("GET /avatar.png", 1002);
            TBegin("Download Body");
            TSleepMs(14);
            TCounter("Bytes Received", 48 * 1024);
            TEnd("Download Body");

            TBegin("Parse JSON"); TSleepMs(6); TEnd("Parse JSON");
            TAsyncEnd("GET /avatar.png", 1002);
        }
        TAsyncEnd("GET /feed.json", 1001);
    });

    pthread_t dbThread = APTSpawnNamed(^{
        pthread_setname_np("DatabaseWriter");
        for (int b = 1; b <= 5; b++) {
            char name[64];
            snprintf(name, sizeof(name), "Write batch #%d", b);
            TBegin(name);
            TSleepMs(4);
            TCounter("Rows Written", b * 40);
            TEnd(name);
        }
    });

    pthread_join(imageThread, NULL);
    pthread_join(networkThread, NULL);
    pthread_join(dbThread, NULL);

    // Phase 3 — a 60-frame render loop with per-frame nested work and live
    // FPS / memory counters that wobble, which draws nicely as graph tracks.
    pthread_t renderThread = APTSpawnNamed(^{
        pthread_setname_np("RenderLoop");
        double memoryMB = 82.0;
        for (int frame = 0; frame < 60; frame++) {
            TBegin("Frame");
            {
                TBegin("Handle Input");    TSleepMs(0.4); TEnd("Handle Input");
                TBegin("Layout");          TSleepMs(0.8); TEnd("Layout");
                TBegin("Tick Animations"); TSleepMs(0.5); TEnd("Tick Animations");
                TBegin("Draw");            TSleepMs(1.2); TEnd("Draw");
                TBegin("Composite");       TSleepMs(0.6); TEnd("Composite");
            }
            TEnd("Frame");

            double fps = 60.0;
            if (frame % 7 == 0) fps -= 4.0;       // occasional hitch
            else if (frame % 3 == 0) fps -= 1.5;
            TCounter("FPS", fps);

            memoryMB += (frame % 10 == 0) ? 6.0 : 0.6;
            if (frame % 17 == 0) memoryMB -= 4.0; // a GC-like dip
            TCounter("Memory (MB)", memoryMB);

            if (frame == 0)  TInstant("first_rendered_frame");
            if (frame == 30) TInstant("user_scrolled");
        }
    });
    pthread_join(renderThread, NULL);

    TInstant("scenario_complete");

    // Required: the writer batches per thread, so flush before the trace is
    // read off the device / simulator (docs/perf-batching-design.md).
    APTFlush();

    return atomic_load(&gShowcaseEvents);
}

#pragma mark - View controller

@interface ViewController ()
@property (nonatomic, strong) UIButton *generateButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UITextView *pathView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1.0];
    [self buildUI];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Convenience for automation (smoke tests / CI): if APPLETRACE_AUTORUN is
    // set, run the showcase once without a tap. Normal use is the button.
    static BOOL autoran = NO;
    if (!autoran && [[[NSProcessInfo processInfo] environment][@"APPLETRACE_AUTORUN"] boolValue]) {
        autoran = YES;
        [self generateTapped];
    }
}

- (void)buildUI {
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    const CGFloat inset = 20.0;
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:inset],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-inset],
        [stack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor constant:inset],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor constant:-inset],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor constant:-2 * inset],
    ]];

    // Title + subtitle.
    UILabel *title = [self labelWithText:@"AppleTrace \U0001F34E"
                                    font:[UIFont boldSystemFontOfSize:32.0]
                                   color:[UIColor colorWithWhite:0.1 alpha:1.0]];
    UILabel *subtitle = [self labelWithText:@"Tap below to generate a sample Perfetto trace, then follow the steps on your Mac."
                                       font:[UIFont systemFontOfSize:16.0]
                                      color:[UIColor colorWithWhite:0.4 alpha:1.0]];
    [stack addArrangedSubview:title];
    [stack addArrangedSubview:subtitle];

    // Generate button.
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:@"▶︎  Generate Trace" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
    button.backgroundColor = [UIColor systemBlueColor];
    button.layer.cornerRadius = 12.0;
    [button addTarget:self action:@selector(generateTapped) forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:52.0].active = YES;
    [stack addArrangedSubview:button];
    self.generateButton = button;

    // Status line.
    self.statusLabel = [self labelWithText:@"Ready."
                                      font:[UIFont systemFontOfSize:15.0]
                                     color:[UIColor colorWithWhite:0.3 alpha:1.0]];
    [stack addArrangedSubview:self.statusLabel];

    // Trace directory card (selectable so you can copy it).
    [stack addArrangedSubview:[self sectionHeader:@"Trace directory on this build"]];
    self.pathView = [self monospaceCardWithText:[NSString stringWithUTF8String:APTGetTraceDirectory()]];
    [stack addArrangedSubview:self.pathView];

    // Step-by-step guidance back on macOS.
    [stack addArrangedSubview:[self sectionHeader:@"Next steps on your Mac"]];
    [stack addArrangedSubview:[self monospaceCardWithText:[self guidanceText]]];
}

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.numberOfLines = 0;
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (UILabel *)sectionHeader:(NSString *)text {
    return [self labelWithText:text
                          font:[UIFont boldSystemFontOfSize:17.0]
                         color:[UIColor colorWithWhite:0.1 alpha:1.0]];
}

- (UITextView *)monospaceCardWithText:(NSString *)text {
    UITextView *view = [[UITextView alloc] init];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.editable = NO;
    view.scrollEnabled = NO;
    view.font = [UIFont fontWithName:@"Menlo" size:12.0];
    view.textColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    view.backgroundColor = [UIColor whiteColor];
    view.layer.cornerRadius = 8.0;
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = [UIColor colorWithWhite:0.85 alpha:1.0].CGColor;
    view.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    view.text = text;
    return view;
}

- (NSString *)guidanceText {
    NSString *dir = [NSString stringWithUTF8String:APTGetTraceDirectory()];
#if TARGET_OS_SIMULATOR
    return [NSString stringWithFormat:
        @"Running in the Simulator, so the trace is already on this Mac.\n\n"
        @"1. Tap “Generate Trace” above.\n\n"
        @"2. In the AppleTrace repo, merge the fragments:\n"
        @"     python3 merge.py -d \"%@\"\n"
        @"   (or:  sh go.sh \"%@\" )\n\n"
        @"3. Open https://ui.perfetto.dev and drag in:\n"
        @"     %@/trace.json\n\n"
        @"Tip: set APPLETRACE_BINARY=1 in the scheme’s environment to try\n"
        @"the compact binary fragment format — merge.py handles both.",
        dir, dir, dir];
#else
    return
        @"Running on a device, so copy the trace to your Mac first.\n\n"
        @"1. Tap “Generate Trace” above.\n\n"
        @"2. Pull the app’s container, either:\n"
        @"   • Xcode ▸ Window ▸ Devices and Simulators ▸\n"
        @"     select this app ▸ ⚙ ▸ Download Container, or\n"
        @"   • xcrun devicectl device copy from --device <id> \\\n"
        @"       --domain-type appDataContainer \\\n"
        @"       --domain-identifier com.everettjf.ManualSectionDemo \\\n"
        @"       --source Library/appletracedata --destination ./trace\n\n"
        @"3. Merge and open in Perfetto:\n"
        @"     python3 merge.py -d <pulled>/Library/appletracedata\n"
        @"   then drag trace.json into https://ui.perfetto.dev";
#endif
}

- (void)generateTapped {
    self.generateButton.enabled = NO;
    self.statusLabel.textColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    self.statusLabel.text = @"Generating trace…";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSUInteger events = APTGenerateShowcase();
        dispatch_async(dispatch_get_main_queue(), ^{
            self.generateButton.enabled = YES;
            self.statusLabel.textColor = [UIColor colorWithRed:0.13 green:0.55 blue:0.13 alpha:1.0];
            self.statusLabel.text = [NSString stringWithFormat:
                @"✅ Captured %lu trace events across 5 threads. Now follow the steps below.",
                (unsigned long)events];
            self.pathView.text = [NSString stringWithUTF8String:APTGetTraceDirectory()];
        });
    });
}

@end
