# AppleTrace Jailbreak Package

This package is for authorized testing on devices you control. It does not
contain a jailbreak or a new injection engine. A Substrate-compatible injector
(for example ElleKit, libhooker, or Substitute) loads `AppleTraceTweak` into
UIKit processes. The constructor remains inactive unless the current bundle id
is present in the preferences allowlist.

```plist
{
    EnabledBundles = (
        "com.example.MyApp"
    );
}
```

The tweak installs AppleTrace's existing arm64/arm64e Objective-C hook and
connects outward to the local `appletraced` Unix socket. Injected applications
do not listen on TCP ports.

## Build

```bash
cd Jailbreak
make package THEOS_PACKAGE_SCHEME=rootless
make clean
make package THEOS_PACKAGE_SCHEME=
```

The package targets iOS 15 or newer and builds arm64 plus arm64e slices. A real
jailbroken device remains required to validate injector compatibility, sandbox
behavior, SpringBoard safety mode, and end-to-end PAC behavior.
