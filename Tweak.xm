// Tweak.xm — vis0g3 main constructor
//
// Injection filter: com.apple.springboard (vis0g3.plist)
// Hook backend: ElleKit (Dopamine) / Substrate compatible
//
// Logos architecture:
//   All %hook blocks live directly in this file (not inside named groups)
//   so that a single %init() call initialises every hook at once.
//   The hook source is logically split into two #included xm files,
//   each of which declares its hooks at file scope.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import "Sources/VZGlobals.h"
#import "Sources/VZPreferences.h"
#import "Sources/VZFaceDatabase.h"


// ── Constructor ───────────────────────────────────────────────────────────────

%ctor {
    @autoreleasepool {
        // Guard: only activate in SpringBoard
        NSString *procName = NSProcessInfo.processInfo.processName;
        if (![procName isEqualToString:@"SpringBoard"]) return;

        // Load preferences from disk before initialising hooks
        [[VZPreferences sharedPreferences] reload];

        // Pre-warm the face database
        __unused id db = [VZFaceDatabase sharedDatabase];

        // Register for live preference updates (respringless)
        static int notifyToken = 0;
        notify_register_dispatch(kVZPrefsChangedNotification.UTF8String,
                                 &notifyToken,
                                 dispatch_get_main_queue(),
                                 ^(int t) {
            [[VZPreferences sharedPreferences] reload];
        });

        // Initialise all hooks from both included files
        %init;

        NSLog(@"[vis0g3] Loaded in SpringBoard.");
    }
}
