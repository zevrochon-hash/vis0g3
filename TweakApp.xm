// TweakApp.xm — vis0g3App companion dylib
//
// Injected into every UIKit-bearing process via the com.apple.UIKit filter.
// Only activates in regular app processes (not SpringBoard, not daemons).
// Hooks LAContext to provide camera facial authentication for:
//   - App biometric prompts
//   - Password AutoFill
//   - Free App Store downloads
//
// SpringBoard-level hooks (lock screen) live in the main vis0g3 dylib.

#import <Foundation/Foundation.h>
#import <notify.h>
#import "Sources/VZGlobals.h"
#import "Sources/VZPreferences.h"
#import "Sources/VZFaceDatabase.h"
#import "Sources/VZAuthViewController.h"


%ctor {
    @autoreleasepool {
        NSString *proc = NSProcessInfo.processInfo.processName;
        // Skip SpringBoard (handled by the main dylib) and known daemons
        if ([proc isEqualToString:@"SpringBoard"]) return;
        if ([proc isEqualToString:@"backboardd"])  return;
        if ([proc isEqualToString:@"mediaserverd"]) return;

        [[VZPreferences sharedPreferences] reload];

        // Register for preference changes
        static int token = 0;
        int *tp = &token;
        notify_register_dispatch(kVZPrefsChangedNotification.UTF8String, tp,
                                 dispatch_get_main_queue(), ^(int t) {
            [[VZPreferences sharedPreferences] reload];
        });

        %init;
    }
}
