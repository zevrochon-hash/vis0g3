#import "VZLivenessChallenge.h"
#import "VZPreferences.h"
#import <math.h>

// ── VZLivenessStep ────────────────────────────────────────────────────────────

@implementation VZLivenessStep

- (NSString *)instruction {
    switch (self.type) {
        case VZLivenessStepLookUp:    return @"Look up";
        case VZLivenessStepLookDown:  return @"Look down";
        case VZLivenessStepTurnLeft:  return @"Turn left";
        case VZLivenessStepTurnRight: return @"Turn right";
        default:                       return @"";
    }
}

@end

// ── VZLivenessChallenge ───────────────────────────────────────────────────────

@implementation VZLivenessChallenge {
    NSMutableArray<VZLivenessStep *> *_steps;
    NSInteger _currentStepIndex;

    // Pose tracking — radians, sampled each frame
    float _baseYaw;    // yaw when step started
    float _basePitch;
    float _minYaw, _maxYaw;
    float _minPitch, _maxPitch;
    BOOL  _baseEstablished;

    NSInteger _noFaceFrames;

    NSTimer *_timeoutTimer;
    dispatch_queue_t _processingQueue;
    BOOL _started;
    BOOL _finished;
}

// ── Factory ───────────────────────────────────────────────────────────────────

+ (instancetype)challengeFromPreferences:(BOOL)randomize {
    VZPreferences *prefs = [VZPreferences sharedPreferences];
    NSMutableArray<NSNumber *> *stepTypes = [NSMutableArray array];

    // Collect enabled step types from preferences
    if (prefs.livenessHeadUpDown || prefs.livenessForeheadChin) {
        // These both require pitch movement; add both directions
        [stepTypes addObject:@(VZLivenessStepLookUp)];
        [stepTypes addObject:@(VZLivenessStepLookDown)];
    }
    if (prefs.livenessHeadLeftRight || prefs.livenessLeftRightTurn) {
        [stepTypes addObject:@(VZLivenessStepTurnLeft)];
        [stepTypes addObject:@(VZLivenessStepTurnRight)];
    }

    // Fallback: at least one step
    if (stepTypes.count == 0) {
        [stepTypes addObject:@(VZLivenessStepLookUp)];
    }

    if (randomize) {
        // Shuffle
        for (NSUInteger i = stepTypes.count - 1; i > 0; i--) {
            NSUInteger j = arc4random_uniform((uint32_t)(i + 1));
            [stepTypes exchangeObjectAtIndex:i withObjectAtIndex:j];
        }
        // "Randomize" also means pick a subset
        NSUInteger count = prefs.livenessMultipleMovements ?
            MIN(stepTypes.count, 3u) : 1u;
        stepTypes = [[stepTypes subarrayWithRange:NSMakeRange(0, count)] mutableCopy];
    } else if (!prefs.livenessMultipleMovements) {
        // Only the first pair (e.g., one axis)
        NSUInteger keep = MIN(stepTypes.count, 2u);
        stepTypes = [[stepTypes subarrayWithRange:NSMakeRange(0, keep)] mutableCopy];
    }

    VZLivenessChallenge *challenge = [[VZLivenessChallenge alloc] init];
    NSMutableArray<VZLivenessStep *> *steps = [NSMutableArray array];
    for (NSNumber *typeNum in stepTypes) {
        VZLivenessStep *step = [[VZLivenessStep alloc] init];
        step.type      = (VZLivenessStepType)typeNum.integerValue;
        step.completed = NO;
        [steps addObject:step];
    }
    challenge->_steps = steps;
    return challenge;
}

// ── Init ──────────────────────────────────────────────────────────────────────

- (instancetype)init {
    self = [super init];
    if (self) {
        _steps           = [NSMutableArray array];
        _currentStepIndex = 0;
        _state           = VZLivenessChallengeStateIdle;
        _processingQueue = dispatch_queue_create("com.zeone.vis0g3.liveness", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

// ── Public API ────────────────────────────────────────────────────────────────

- (void)start {
    if (_steps.count == 0) {
        // No steps — trivially complete
        [self _succeed];
        return;
    }
    _state   = VZLivenessChallengeStateWaitingForFace;
    _started = YES;
    _finished = NO;
    [self _resetPoseTracking];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self _updateProgress];
        self->_timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:kVZLivenessTimeout
                                                               target:self
                                                             selector:@selector(_onTimeout)
                                                             userInfo:nil
                                                              repeats:NO];
    });
}

- (void)cancel {
    [self _finish:NO error:[NSError errorWithDomain:kVZErrorDomain
                                              code:VZErrorCodeLivenessFailed
                                          userInfo:@{NSLocalizedDescriptionKey:@"Cancelled."}]];
}

- (NSArray<VZLivenessStep *> *)steps { return [_steps copy]; }

- (NSString *)currentInstruction {
    if (_currentStepIndex < (NSInteger)_steps.count) {
        return _steps[_currentStepIndex].instruction;
    }
    if (_state == VZLivenessChallengeStateComplete) return @"Verification complete";
    return @"Look at the camera";
}

- (float)overallProgress {
    if (_steps.count == 0) return 1.0;
    NSInteger done = 0;
    for (VZLivenessStep *s in _steps) { if (s.completed) done++; }
    return (float)done / (float)_steps.count;
}

// ── Frame processing ──────────────────────────────────────────────────────────

- (void)processFaceObservation:(VNFaceObservation *)observation {
    if (!_started || _finished) return;

    // Extract pose
    float yaw   = 0, pitch = 0;
    if (observation.yaw) yaw   = observation.yaw.floatValue;
    if (@available(iOS 14.0, *)) {
        if (observation.pitch) pitch = observation.pitch.floatValue;
    }
    // Estimate pitch from landmarks when not available
    if (pitch == 0 && observation.landmarks) {
        pitch = [self _estimatePitchFromLandmarks:observation.landmarks];
    }

    dispatch_async(_processingQueue, ^{
        [self _processPose:yaw pitch:pitch];
    });

    _noFaceFrames = 0;
    if (_state == VZLivenessChallengeStateWaitingForFace) {
        _state = VZLivenessChallengeStateActive;
    }
}

- (void)processNoFace {
    if (!_started || _finished) return;
    _noFaceFrames++;
    // If face disappears for too long during a challenge, fail
    if (_noFaceFrames > 30) {
        [self _finish:NO error:[NSError errorWithDomain:kVZErrorDomain
                                                  code:VZErrorCodeLivenessFailed
                                              userInfo:@{NSLocalizedDescriptionKey:
                                                             @"Face disappeared during liveness check."}]];
    }
}

// ── Pose processing ───────────────────────────────────────────────────────────

- (void)_processPose:(float)yaw pitch:(float)pitch {
    if (_currentStepIndex >= (NSInteger)_steps.count) return;
    VZLivenessStep *step = _steps[_currentStepIndex];
    if (step.completed) return;

    if (!_baseEstablished) {
        _baseYaw   = yaw;
        _basePitch = pitch;
        _minYaw    = yaw;   _maxYaw   = yaw;
        _minPitch  = pitch; _maxPitch = pitch;
        _baseEstablished = YES;
        return;
    }

    _minYaw   = MIN(_minYaw, yaw);     _maxYaw   = MAX(_maxYaw, yaw);
    _minPitch = MIN(_minPitch, pitch); _maxPitch = MAX(_maxPitch, pitch);

    BOOL stepDone = NO;
    switch (step.type) {
        case VZLivenessStepLookUp:
            // pitch increases when looking up in Vision coordinate space
            stepDone = (_maxPitch - _basePitch) > kVZLivenessPitchThreshold;
            break;
        case VZLivenessStepLookDown:
            stepDone = (_basePitch - _minPitch) > kVZLivenessPitchThreshold;
            break;
        case VZLivenessStepTurnLeft:
            // Negative yaw = looking left
            stepDone = (_baseYaw - _minYaw) > kVZLivenessYawThreshold;
            break;
        case VZLivenessStepTurnRight:
            // Positive yaw = looking right
            stepDone = (_maxYaw - _baseYaw) > kVZLivenessYawThreshold;
            break;
        default:
            break;
    }

    if (stepDone) {
        dispatch_async(dispatch_get_main_queue(), ^{
            step.completed = YES;
            self->_currentStepIndex++;
            [self _resetPoseTracking];
            if (self->_currentStepIndex >= (NSInteger)self->_steps.count) {
                [self _succeed];
            } else {
                [self _updateProgress];
            }
        });
    }
}

- (float)_estimatePitchFromLandmarks:(VNFaceLandmarks2D *)lm {
    // Use vertical position of nose relative to eyes as a pitch proxy
    if (!lm.nose || !lm.leftEye || !lm.rightEye) return 0;
    const CGPoint *nosePts = lm.nose.normalizedPoints;
    const CGPoint *lEyePts = lm.leftEye.normalizedPoints;
    const CGPoint *rEyePts = lm.rightEye.normalizedPoints;
    if (lm.nose.pointCount == 0 || lm.leftEye.pointCount == 0 || lm.rightEye.pointCount == 0) return 0;
    CGFloat noseY = nosePts[0].y;
    CGFloat eyeY  = (lEyePts[0].y + rEyePts[0].y) * 0.5;
    // Positive = nose below eyes (looking up), negative = nose above eyes (looking down)
    return (float)(noseY - eyeY) * 2.0f;
}

// ── Internal state transitions ────────────────────────────────────────────────

- (void)_resetPoseTracking {
    _baseEstablished = NO;
    _noFaceFrames    = 0;
}

- (void)_succeed {
    [self _finish:YES error:nil];
}

- (void)_onTimeout {
    if (_finished) return;
    [self _finish:NO error:[NSError errorWithDomain:kVZErrorDomain
                                              code:VZErrorCodeLivenessTimeout
                                          userInfo:@{NSLocalizedDescriptionKey:
                                                         @"Liveness check timed out."}]];
}

- (void)_finish:(BOOL)success error:(nullable NSError *)error {
    if (_finished) return;
    _finished = YES;
    _state    = success ? VZLivenessChallengeStateComplete : VZLivenessChallengeStateFailed;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_timeoutTimer invalidate];
        self->_timeoutTimer = nil;
        if (self->_doneBlock) self->_doneBlock(success, error);
    });
}

- (void)_updateProgress {
    NSString *instr = self.currentInstruction;
    float    prog   = self.overallProgress;
    if (_progressBlock) _progressBlock(instr, prog);
}

@end
