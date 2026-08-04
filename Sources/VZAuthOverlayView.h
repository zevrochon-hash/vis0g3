#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VZAuthAnimationState) {
    VZAuthAnimationStateIdle,
    VZAuthAnimationStateScanning,
    VZAuthAnimationStateLiveness,
    VZAuthAnimationStateSuccess,
    VZAuthAnimationStateFailure,
};

/// Face authentication animated overlay — modern Face ID-inspired glyph,
/// scanning ring, liveness instruction banner, and status readout.
/// Fully implemented in Core Animation; no private assets required.
@interface VZAuthOverlayView : UIView

@property (nonatomic) VZAuthAnimationState animationState;

/// Update the liveness instruction text (shown below the glyph).
- (void)setLivenessInstruction:(nullable NSString *)instruction progress:(float)progress;

/// Show the scanning pulse animation.
- (void)startScanAnimation;

/// Stop all animations and show idle state.
- (void)stopAnimations;

/// Transition to success state with haptic feedback.
- (void)transitionToSuccess;

/// Transition to failure state.
- (void)transitionToFailure;

/// Transition back to scanning after a failure (retry).
- (void)transitionToScanning;

@end

NS_ASSUME_NONNULL_END
