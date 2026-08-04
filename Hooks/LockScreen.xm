// Hooks/LockScreen.xm
// Intercepts the iOS 16 lock screen biometric authentication flow and replaces
// it with vis0g3 camera-based facial recognition.
//
// Hook targets (iOS 16 / Dopamine / SpringBoard):
//   SBUIBiometricResource  — manages biometric UI state on the cover sheet
//   SBLockScreenManager    — detects lock/wake transitions
//   SBFingerprintRecognitionManager — intercepts Touch ID result delivery (iPhone 8)
//   SBPasscodeManager       — used to programmatically succeed authentication
//
// Private headers derived from public class-dumps and open-source headers.
// Availability is checked at runtime before use.

#import "../Sources/VZGlobals.h"
#import "../Sources/VZPreferences.h"
#import "../Sources/VZFaceDatabase.h"
#import "../Sources/VZAuthViewController.h"
#import <UIKit/UIKit.h>

// ── Forward-declare private classes ──────────────────────────────────────────

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
- (void)unlockUIFromSource:(NSInteger)source withOptions:(id)options;
@end

@interface SBPasscodeManager : NSObject
+ (instancetype)sharedManager;
- (void)successfulAuthenticationWithRequest:(id)req presencePolicy:(NSInteger)policy policy:(NSInteger)pol;
@end

@interface SBUIBiometricResource : NSObject
- (void)enableBiometricFromSource:(NSInteger)source;
- (void)_notifyBiometricSuccess;
- (void)_notifyBiometricFailureWithError:(NSError *)error;
@end

// ── Module-level state ────────────────────────────────────────────────────────

static BOOL gLockScreenAuthPresented     = NO;
static UIViewController *gAuthParentVC   = nil;

// Present our auth VC from the key window's root VC
static void PresentLockScreenAuth(void) {
    if (gLockScreenAuthPresented) return;
    if (![VZPreferences sharedPreferences].enabled) return;
    if ([VZFaceDatabase sharedDatabase].profiles.count == 0) return;

    UIViewController *rootVC = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) { rootVC = w.rootViewController; break; }
                }
            }
            if (rootVC) break;
        }
    }
    if (!rootVC) {
        rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    }
    if (!rootVC) return;

    // Walk to the topmost presented controller
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    gAuthParentVC = rootVC;
    gLockScreenAuthPresented = YES;

    [VZAuthViewController presentFromViewController:rootVC completion:^(VZAuthResult result) {
        gLockScreenAuthPresented = NO;
        gAuthParentVC            = nil;

        switch (result) {
            case VZAuthResultSuccess: {
                // Unlock the device via SBPasscodeManager
                dispatch_async(dispatch_get_main_queue(), ^{
                    id pm = [%c(SBPasscodeManager) respondsToSelector:@selector(sharedManager)]
                             ? [%c(SBPasscodeManager) sharedManager] : nil;
                    if (pm && [pm respondsToSelector:@selector(successfulAuthenticationWithRequest:presencePolicy:policy:)]) {
                        [pm successfulAuthenticationWithRequest:nil presencePolicy:1 policy:0];
                    } else {
                        // Fallback: try unlocking via SBLockScreenManager
                        id lm = [%c(SBLockScreenManager) respondsToSelector:@selector(sharedInstance)]
                                  ? [%c(SBLockScreenManager) sharedInstance] : nil;
                        if (lm && [lm respondsToSelector:@selector(unlockUIFromSource:withOptions:)]) {
                            [lm unlockUIFromSource:5 withOptions:nil];
                        }
                    }

                    // Optional direct Home Screen
                    if ([VZPreferences sharedPreferences].directHomeScreen) {
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                            id lm = [%c(SBLockScreenManager) respondsToSelector:@selector(sharedInstance)]
                                      ? [%c(SBLockScreenManager) sharedInstance] : nil;
                            if (lm && [lm respondsToSelector:@selector(unlockUIFromSource:withOptions:)]) {
                                [lm unlockUIFromSource:5 withOptions:nil];
                            }
                        });
                    }
                });
                break;
            }
            case VZAuthResultFallback:
            case VZAuthResultCancelled:
            case VZAuthResultFailure:
                // Passcode UI remains available normally — nothing to do
                break;
        }
    }];
}

// ── SBLockScreenManager — detect device waking to locked state ────────────────

%hook SBLockScreenManager

- (void)_handleLockUIRequested {
    %orig;
}

// Called each time the screen wakes while locked
- (void)_handleActivationUILockStateChanged {
    %orig;
    if (![%c(SBLockScreenManager) respondsToSelector:@selector(sharedInstance)]) return;
    id shared = [%c(SBLockScreenManager) sharedInstance];
    if (![shared isUILocked]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        PresentLockScreenAuth();
    });
}

%end

// ── SBUIBiometricResource — iOS 16 cover sheet biometric activation ───────────

%hook SBUIBiometricResource

- (void)enableBiometricFromSource:(NSInteger)source {
    if (![VZPreferences sharedPreferences].enabled) {
        %orig;
        return;
    }
    if ([VZFaceDatabase sharedDatabase].profiles.count == 0) {
        %orig;
        return;
    }
    // Don't call %orig — we replace the biometric request
    dispatch_async(dispatch_get_main_queue(), ^{
        PresentLockScreenAuth();
    });
}

%end

// ── Ensure cleanup on SpringBoard restart ────────────────────────────────────

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    gLockScreenAuthPresented = NO;
}

%end
