// Hooks/Authentication.xm
// Intercepts LocalAuthentication framework biometric calls and replaces them
// with vis0g3 camera facial recognition.

#import "../Sources/VZGlobals.h"
#import "../Sources/VZPreferences.h"
#import "../Sources/VZFaceDatabase.h"
#import "../Sources/VZAuthViewController.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <UIKit/UIKit.h>

%hook LAContext

- (void)evaluatePolicy:(LAPolicy)policy
       localizedReason:(NSString *)localizedReason
                 reply:(void (^)(BOOL success, NSError *error))reply {

    VZPreferences *prefs = [VZPreferences sharedPreferences];

    BOOL isBiometricOnly =
        (policy == LAPolicyDeviceOwnerAuthenticationWithBiometrics);

    if (!prefs.enabled ||
        !prefs.appAuthEnabled ||
        [VZFaceDatabase sharedDatabase].profiles.count == 0 ||
        !isBiometricOnly) {

        %orig;
        return;
    }

    // Find the active application's key window.
    UIWindow *keyWindow = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {

            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;

            UIWindowScene *windowScene = (UIWindowScene *)scene;

            if (windowScene.activationState !=
                UISceneActivationStateForegroundActive)
                continue;

            for (UIWindow *window in windowScene.windows) {

                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }

            if (keyWindow)
                break;
        }
    }

    if (!keyWindow) {
        %orig;
        return;
    }

    UIViewController *rootVC = keyWindow.rootViewController;

    if (!rootVC) {
        %orig;
        return;
    }

    // Find the currently visible view controller.
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }

    // Create vis0g3's custom face authentication screen.
    VZAuthViewController *authVC =
        [[VZAuthViewController alloc] init];

    authVC.showPasscodeFallback = NO;
    authVC.modalPresentationStyle =
        UIModalPresentationOverFullScreen;
    authVC.modalTransitionStyle =
        UIModalTransitionStyleCrossDissolve;

    authVC.completion = ^(VZAuthResult result) {

        dispatch_async(dispatch_get_main_queue(), ^{

            switch (result) {

                case VZAuthResultSuccess:
                    reply(YES, nil);
                    break;

                case VZAuthResultFallback:
                case VZAuthResultCancelled: {

                    NSError *cancelError =
                        [NSError errorWithDomain:
                            @"com.apple.LocalAuthentication"
                            code:-2
                            userInfo:nil];

                    reply(NO, cancelError);
                    break;
                }

                case VZAuthResultFailure: {

                    NSError *failureError =
                        [NSError errorWithDomain:
                            @"com.apple.LocalAuthentication"
                            code:-1
                            userInfo:nil];

                    reply(NO, failureError);
                    break;
                }
            }
        });
    };

    [rootVC presentViewController:authVC
                          animated:YES
                        completion:nil];
}


// Tell applications that vis0g3 has biometric authentication available.

- (BOOL)canEvaluatePolicy:(LAPolicy)policy
                    error:(NSError **)outError {

    VZPreferences *prefs =
        [VZPreferences sharedPreferences];

    if (prefs.enabled &&
        prefs.appAuthEnabled &&
        [VZFaceDatabase sharedDatabase].profiles.count > 0 &&
        policy == LAPolicyDeviceOwnerAuthenticationWithBiometrics) {

        if (outError)
            *outError = nil;

        return YES;
    }

    return %orig;
}


// Tell applications that the available biometric type is Face ID.

- (LABiometryType)biometryType {

    VZPreferences *prefs =
        [VZPreferences sharedPreferences];

    if (prefs.enabled &&
        prefs.appAuthEnabled &&
        [VZFaceDatabase sharedDatabase].profiles.count > 0) {

        if (@available(iOS 11.0, *)) {
            return LABiometryTypeFaceID;
        }
    }

    return %orig;
}

%end
