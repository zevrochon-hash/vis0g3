#pragma once
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import "VZGlobals.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VZLivenessChallengeState) {
    VZLivenessChallengeStateIdle,
    VZLivenessChallengeStateWaitingForFace,
    VZLivenessChallengeStateActive,    // performing steps
    VZLivenessChallengeStateComplete,
    VZLivenessChallengeStateFailed,    // timeout or bad movement
};

/// One step in a liveness challenge (e.g., "look left")
@interface VZLivenessStep : NSObject
@property (nonatomic) VZLivenessStepType type;
@property (nonatomic) BOOL               completed;
/// Human-readable instruction for this step.
@property (nonatomic, readonly) NSString *instruction;
@end

// ─────────────────────────────────────────────────────────────────────────────

typedef void (^VZLivenessChallengeProgressBlock)(NSString *instruction, float progress);
typedef void (^VZLivenessChallengeDoneBlock)(BOOL success, NSError *_Nullable error);

@interface VZLivenessChallenge : NSObject

@property (nonatomic, readonly) VZLivenessChallengeState state;
@property (nonatomic, readonly) NSArray<VZLivenessStep *> *steps;
@property (nonatomic, readonly) NSString *currentInstruction;
@property (nonatomic, readonly) float overallProgress;  // 0..1

/// Called on main queue when a step changes or progress updates.
@property (nonatomic, copy, nullable) VZLivenessChallengeProgressBlock progressBlock;
/// Called on main queue when the challenge finishes (success or failure).
@property (nonatomic, copy, nullable) VZLivenessChallengeDoneBlock     doneBlock;

/// Build a challenge from the current preference settings.
/// @param randomize  Randomize step order / selection when enabled.
+ (instancetype)challengeFromPreferences:(BOOL)randomize;

/// Begin the challenge. Starts the timeout timer.
- (void)start;

/// Cancel the challenge.
- (void)cancel;

/// Feed a face observation (called every camera frame from the camera controller).
/// Internally updates pitch/yaw tracking and advances step completion.
- (void)processFaceObservation:(VNFaceObservation *)observation;

/// Feed a "no face" condition (called when no face is detected in frame).
- (void)processNoFace;

@end

NS_ASSUME_NONNULL_END
