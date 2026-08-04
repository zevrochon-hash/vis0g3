#pragma once
#import <UIKit/UIKit.h>
#import "VZGlobals.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^VZAuthCompletionBlock)(VZAuthResult result);

/// Full-screen authentication UI.
///
/// Presents the camera preview, animated Face ID-style overlay, liveness
/// challenge instructions, and passcode fallback button.  Drives the
/// VZCameraController, VZFaceRecognizer, and VZLivenessChallenge internally.
///
/// Call +presentFromViewController:completion: for lock-screen contexts.
/// Call +presentForLocalAuthFromViewController:completion: for LAContext contexts.
@interface VZAuthViewController : UIViewController

/// Maximum recognition attempts before the VC automatically gives up
/// and calls completion with VZAuthResultFailure.
@property (nonatomic) NSInteger maxAttempts;   // default: 5

/// Whether to show a "Enter Passcode" fallback button.
@property (nonatomic) BOOL showPasscodeFallback;  // default: YES

/// Completion block called on the main queue once auth finishes.
@property (nonatomic, copy, nullable) VZAuthCompletionBlock completion;

/// Convenience: present from a parent VC and start recognition immediately.
+ (instancetype)presentFromViewController:(UIViewController *)parent
                               completion:(nullable VZAuthCompletionBlock)completion;

/// Start the auth flow programmatically (called automatically on viewDidAppear
/// if not already started).
- (void)beginAuthentication;

/// Cancel and dismiss, calling completion with VZAuthResultCancelled.
- (void)cancelAuthentication;

@end

NS_ASSUME_NONNULL_END
