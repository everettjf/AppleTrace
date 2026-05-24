//
//  CAppleTrace.h
//  Public umbrella header for the SwiftPM C target.
//
//  Re-exports the existing AppleTrace public C API (declared in the Xcode
//  framework's header) so Swift can `import CAppleTrace` without duplicating
//  the declarations. The single source of truth stays in
//  appletrace/appletrace/src/appletrace.h.
//

#import "../../../appletrace/appletrace/src/appletrace.h"
