# AppleTrace 中文说明

AppleTrace 是一个面向 iOS 的方法追踪与调用链分析工具，可以把运行时事件导出成 Chrome Trace 格式进行可视化分析。

## 2026 现代化改进

- Python 工具链已升级到 Python 3。
- 新增统一命令行入口：`scripts/appletrace_cli.py`。
- 新增自动化测试：`python3 -m pytest tests`。
- 新增运行时控制 API：`APTFlush`、`APTSetEnabled`、`APTIsEnabled`、`APTGetTraceDirectory`。
- 支持通过环境变量配置 trace 输出目录和 mmap 块大小。

## 当前 hook 状态

- 稳定主线：手动 section 与延迟安装的 `objc_msgSend` direct hook 已有 simulator smoke test 覆盖。
- 实验支线：sample 自身的嵌套 Objective-C 方法调用与跨线程 trace 现在也有自动化覆盖。
- 发布建议：把 direct hook 视为 arm64 预览能力，生产上仍可继续把手动埋点作为最低风险基线。

## 快速开始

```bash
brew install python ldid git
git clone https://github.com/everettjf/AppleTrace.git
cd AppleTrace
sh get_catapult.sh
python3 -m pip install -r requirements.txt
```

### 合并与导出

```bash
python3 merge.py -d /path/to/appletracedata
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
```

## 测试

```bash
python3 -m pytest tests
./scripts/test_objc_msgsend_hook.sh
./scripts/test_objc_msgsend_hook_experimental.sh
```

其中：

- `test_objc_msgsend_hook.sh` 是当前可发布的稳定验证链路。
- `test_objc_msgsend_hook_experimental.sh` 会验证 sample 方法级 trace、跨线程事件以及 section 闭合情况。

## 说明

仓库 README 已明确标注该项目处于 maintenance mode。当前这轮改造的目标不是重写架构，而是把工程基础、可验证性和使用体验拉到更现代的水平。
