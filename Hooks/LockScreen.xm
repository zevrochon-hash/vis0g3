// Hooks/LockScreen.xm

#import "../Sources/VZGlobals.h"
#import "../Sources/VZPreferences.h"
#import "../Sources/VZFaceDatabase.h"
#import "../Sources/VZAuthViewController.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

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

static BOOL gLockScreenAuthPresented = NO;

// ── Helper: resolve root view controller ─────────────────────────────────────

static UIViewController *VZTopViewController(void) {
    UIViewController *rootVC = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) { rootVC = w.rootViewController; break; }
                }
            }
            if (rootVC) break;
        }
    }

    if (!rootVC) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
#pragma clang diagnostic pop
    }

    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

// ── Helper: call unlock on the system ────────────────────────────────────────

static void VZTriggerSystemUnlock(void) {
    Class pmClass = objc_getClass("SBPasscodeManager");
    if (pmClass && [pmClass respondsToSelector:@selector(sharedManager)]) {
        id pm = [pmClass performSelector:@selector(sharedManager)];
        SEL authSel = @selector(successfulAuthenticationWithRequest:presencePolicy:policy:);
        if (pm && [pm respondsToSelector:authSel]) {
            [pm successfulAuthenticationWithRequest:nil presencePolicy:1 policy:0];
            return;
        }
    }

    Class lmClass = objc_getClass("SBLockScreenManager");
    if (lmClass && [lmClass respondsToSelector:@selector(sharedInstance)]) {
        id lm = [lmClass performSelector:@selector(sharedInstance)];
        SEL unlockSel = @selector(unlockUIFromSource:withOptions:);
        if (lm && [lm respondsToSelector:unlockSel]) {
            NSInvocation *inv = [NSInvocation
                invocationWithMethodSignature:[lm methodSignatureForSelector:unlockSel]];
            inv.target   = lm;
            inv.selector = unlockSel;
            NSInteger src = 5;
            id opts = nil;
            [inv setArgument:&src  atIndex:2];
            [inv setArgument:&opts atIndex:3];
            [inv invoke];
        }
    }
}

// ── Present vis0g3 auth on the lock screen ────────────────────────────────────

static void PresentLockScreenAuth(void) {
    if (gLockScreenAuthPresented) return;
    if (![VZPreferences sharedPreferences].enabled) return;
    if ([VZFaceDatabase sharedDatabase].profiles.count == 0) return;

    UIViewController *rootVC = VZTopViewController();
    if (!rootVC) return;

    gLockScreenAuthPresented = YES;

    [VZAuthViewController presentFromViewController:rootVC completion:^(VZAuthResult result) {
        gLockScreenAuthPresented = NO;

        if (result == VZAuthResultSuccess) {
            dispatch_async(dispatch_get_main_queue(), ^{
                VZTriggerSystemUnlock();

                if ([VZPreferences sharedPreferences].directHomeScreen) {
                    dispatch_after(
                        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
                        VZTriggerSystemUnlock();
                    });
                }
            });
        }
    }];
}

// ── SBLockScreenManager — detect device waking while locked ──────────────────

%hook SBLockScreenManager

- (void)_handleActivationUILockStateChanged {
    %orig;
    BOOL locked = NO;
    if ([self respondsToSelector:@selector(isUILocked)]) {
        locked = [self isUILocked];
    }
    if (!locked) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        PresentLockScreenAuth();
    });
}

%end

// ── SBUIBiometricResource — intercept Touch ID activation on cover sheet ──────

%hook SBUIBiometricResource

- (void)enableBiometricFromSource:(NSInteger)source {
    if (![VZPreferences sharedPreferences].enabled ||
        [VZFaceDatabase sharedDatabase].profiles.count == 0) {
        %orig;
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        PresentLockScreenAuth();
    });
}

%end

// ── SpringBoard — clean up state on launch ────────────────────────────────────

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    gLockScreenAuthPresented = NO;
}

%end
