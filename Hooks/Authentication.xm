// Hooks/Authentication.xm
// Intercepts LocalAuthentication framework biometric calls and replaces them
// with vis0g3 camera facial recognition.
//
// Hooked: -[LAContext evaluatePolicy:localizedReason:reply:]
//
// Apple Pay, paid App Store purchases, and kiosk/secure-enclave-required
// policies are deliberately NOT intercepted — those fall through to the
// normal Touch ID / passcode path.

#import "../Sources/VZGlobals.h"
#import "../Sources/VZPreferences.h"
#import "../Sources/VZFaceDatabase.h"
#import "../Sources/VZAuthViewController.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <UIKit/UIKit.h>

// ── LAContext hook ────────────────────────────────────────────────────────────

%hook LAContext

- (void)evaluatePolicy:(LAPolicy)policy
       localizedReason:(NSString *)localizedReason
                 reply:(void(^)(BOOL success, NSError *error))reply {

    VZPreferences *prefs = [VZPreferences sharedPreferences];

    // Pass through if:
    //  - tweak is disabled
    //  - app auth hook is off
    //  - no faces enrolled
    //  - policy is device-owner (passcode+biometric) but NOT biometric-only
    //    (LAPolicyDeviceOwnerAuthentication = 1, biometric only = 2)
    //  - policy requires the secure enclave specifically
    BOOL isBiometricOnly = (policy == LAPolicyDeviceOwnerAuthenticationWithBiometrics);
    if (!prefs.enabled || !prefs.appAuthEnabled ||
        ![VZFaceDatabase sharedDatabase].profiles.count ||
        !isBiometricOnly) {
        %orig;
        return;
    }

    // Find the topmost view controller to present on
    UIViewController *rootVC = nil;


    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }

    if (!rootVC) {
        // No window to present from — fall back to system auth
        %orig;
        return;
    }

    // Present vis0g3 auth
    VZAuthViewController *authVC = [[VZAuthViewController alloc] init];
    authVC.showPasscodeFallback  = NO;  // app controls its own fallback
    authVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    authVC.modalTransitionStyle   = UIModalTransitionStyleCrossDissolve;

    authVC.completion = ^(VZAuthResult result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            switch (result) {
                case VZAuthResultSuccess:
                    reply(YES, nil);
                    break;
                case VZAuthResultFallback:
                case VZAuthResultCancelled: {
                    // Return LAError userCancel so the app shows its own fallback
                    NSError *cancelErr = [NSError errorWithDomain:@"com.apple.LocalAuthentication"
                                                            code:-2  // LAErrorUserCancel
                                                        userInfo:nil];
                    reply(NO, cancelErr);
                    break;
                }
                case VZAuthResultFailure: {
                    NSError *failErr = [NSError errorWithDomain:@"com.apple.LocalAuthentication"
                                                          code:-1  // LAErrorAuthenticationFailed
                                                      userInfo:nil];
                    reply(NO, failErr);
                    break;
                }
            }
        });
    };

    [rootVC presentViewController:authVC animated:YES completion:nil];
}

// ── canEvaluatePolicy — report biometrics as available ────────────────────────

- (BOOL)canEvaluatePolicy:(LAPolicy)policy error:(NSError **)outError {
    VZPreferences *prefs = [VZPreferences sharedPreferences];
    if (prefs.enabled && prefs.appAuthEnabled &&
        [VZFaceDatabase sharedDatabase].profiles.count > 0 &&
        policy == LAPolicyDeviceOwnerAuthenticationWithBiometrics) {
        if (outError) *outError = nil;
        return YES;
    }
    return %orig;
}

// ── biometryType — advertise face-style biometry ─────────────────────────────

- (LABiometryType)biometryType {
    VZPreferences *prefs = [VZPreferences sharedPreferences];
    if (prefs.enabled && prefs.appAuthEnabled &&
        [VZFaceDatabase sharedDatabase].profiles.count > 0) {
        // Report as Face ID so app UIs show the correct icon/string where possible
        if (@available(iOS 11.0, *)) {
            return LABiometryTypeFaceID;
        }
    }
    return %orig;
}

%end
