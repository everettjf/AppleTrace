# AppleTrace 中文说明

AppleTrace 是一个面向 iOS 的方法追踪与调用链分析工具，可以把运行时事件导出成 Chrome Trace 格式进行可视化分析。

> 🚀 AppleTrace 正在持续开发中：轻量、可内嵌、产物可直接在 Perfetto/Chrome 中分享。
> 下一步规划见 [ROADMAP.md](ROADMAP.md)。

## 最新改进

- **更快的 `objc_msgSend` hook**：对 `(Class, SEL)` 做名字 interning，配合每线程零分配调用栈，热路径不再每次 `malloc`/`snprintf`。
- **线程命名**：trace 现在会标注线程名，Perfetto/Chrome 中不再只显示裸 id。
- **更多事件类型**：除 begin/end section 外，新增 `APTInstant`（瞬时标记）与 `APTCounter`（内存、FPS 等数值曲线）。
- **运行时过滤**：通过类名前缀 allow/deny 列表限制自动 trace 的范围
  （`APPLETRACE_TRACE_CLASS_ALLOW` / `APPLETRACE_TRACE_CLASS_DENY`）。
- **Perfetto 优先可视化**：把 `trace.json` 拖入 [ui.perfetto.dev](https://ui.perfetto.dev) 即可，无需下载（Catapult HTML 导出仍可离线使用）。
- Python 3 工具链、统一 CLI（`scripts/appletrace_cli.py`）、自动化测试、CI，以及面向大 trace 的流式合并。
- 运行时控制 API：`APTFlush`、`APTSetEnabled`、`APTIsEnabled`、`APTGetTraceDirectory`，并支持通过环境变量配置输出目录与 mmap 块大小。

## 当前 hook 状态

- 稳定主线：手动 section 与延迟安装的 `objc_msgSend` direct hook 已有 simulator smoke test 覆盖。
- 实验支线：sample 自身的嵌套 Objective-C 方法调用、`objc_msgSendSuper2`、跨线程 trace、一个 10 参数 Objective-C 调用、浮点参数/返回值，以及小型聚合返回值现在也有自动化覆盖。
- 发布建议：把 direct hook 视为 arm64 预览能力，生产上仍可继续把手动埋点作为最低风险基线。

## 快速开始

```bash
brew install python ldid git
git clone https://github.com/everettjf/AppleTrace.git
cd AppleTrace
sh get_catapult.sh
python3 -m pip install -r requirements.txt
```

### 合并与可视化

```bash
# 合并 trace 片段
python3 merge.py -d /path/to/appletracedata

# 推荐：把生成的 trace.json 拖入 https://ui.perfetto.dev 直接查看
# 或离线生成 Catapult HTML：
python3 scripts/appletrace_cli.py all /path/to/appletracedata --open
sh go.sh /path/to/appletracedata
```

### 手动埋点

```objc
#import <appletrace/appletrace.h>

- (void)viewDidLoad {
    APTBegin;
    [super viewDidLoad];
    APTEnd;
}
```

### C++ 作用域埋点

```cpp
#include <appletrace/appletrace.h>

void runTask() {
    APTScopeSection("task");
}
```

### 瞬时标记与计数器

```objc
APTInstant("cache_miss");          // 在当前线程时间线上打一个点
APTCounter("resident_mb", 142.5);  // 随时间绘制数值曲线
APTCounter("fps", 60);
```

### 运行时控制

```objc
APTSetEnabled(NO);
APTSetEnabled(YES);
APTFlush();
NSLog(@"trace dir = %s", APTGetTraceDirectory());
```

## 环境变量

```bash
export APPLETRACE_ENABLED=1
export APPLETRACE_DATA_DIR="$HOME/tmp/appletracedata"
export APPLETRACE_BLOCK_SIZE_MB=32
export APPLETRACE_KEEP_EXISTING=1

# arm64 自动 objc_msgSend hook
export APPLETRACE_AUTO_HOOK_OBJC_MSGSEND=1
# 仅 trace 这些类名前缀（逗号分隔）
export APPLETRACE_TRACE_CLASS_ALLOW="MyApp,UI"
# 永不 trace 这些类名前缀（优先级高于 allow）
export APPLETRACE_TRACE_CLASS_DENY="NSKVO,_"
```

## 测试

```bash
python3 -m pytest tests
./scripts/test_objc_msgsend_hook.sh
./scripts/test_objc_msgsend_hook_experimental.sh
```

其中：

- `test_objc_msgsend_hook.sh` 是当前可发布的稳定验证链路。
- `test_objc_msgsend_hook_experimental.sh` 会验证 sample 方法级 trace、`super` 调用、跨线程事件、section 闭合情况、栈上传参的 Objective-C 调用、浮点参数和返回值，以及小型聚合返回值。

## 说明

AppleTrace 的定位是「轻量、可内嵌、产物可分享」的方法级 tracer。这一轮改造在保持
该定位的前提下，重点提升了热路径性能、事件表达能力（instant/counter/线程名）以及
基于 Perfetto 的现代可视化体验。后续规划详见 [ROADMAP.md](ROADMAP.md)，欢迎贡献。
