//
//  appletrace_impl.mm
//  Compiles the existing AppleTrace core into the SwiftPM C target.
//
//  Rather than duplicate the implementation, this pulls in the canonical
//  source from the Xcode framework tree so both build systems share one copy.
//  Only the manual-instrumentation core is included here; the arm64
//  objc_msgSend hook stays in the Xcode project.
//

#include "../../appletrace/appletrace/src/appletrace.mm"
