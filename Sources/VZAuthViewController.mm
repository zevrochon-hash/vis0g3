#import "VZAuthViewController.h"
#import "VZCameraController.h"
#import "VZFaceRecognizer.h"
#import "VZLivenessChallenge.h"
#import "VZPreferences.h"
#import "VZFaceDatabase.h"
#import "VZAuthOverlayView.h"

static const NSInteger kVZDefaultMaxAttempts = 5;
// Seconds to show success/failure before dismissing
static const NSTimeInterval kVZSuccessHoldDuration = 0.85;
static const NSTimeInterval kVZFailureHoldDuration = 1.2;
// Seconds of idle camera before showing "No face detected" message
static const NSTimeInterval kVZNoFaceWarningDelay   = 2.5;

typedef NS_ENUM(NSInteger, VZAuthPhase) {
    VZAuthPhaseIdle,
    VZAuthPhaseRecognizing,
    VZAuthPhaseLiveness,
    VZAuthPhaseSuccess,
    VZAuthPhaseFailure,
    VZAuthPhaseDone,
};

@implementation VZAuthViewController {
    // Camera
    VZCameraController  *_camera;
    VZFaceRecognizer    *_recognizer;
    AVCaptureVideoPreviewLayer *_previewLayer;

    // Liveness
    VZLivenessChallenge *_livenessChallenge;
    VZFaceProfile       *_recognizedProfile;

    // UI
    UIView              *_previewContainer;
    VZAuthOverlayView   *_overlay;
    UIView              *_blurContainer;
    UIVisualEffectView  *_blurView;
    UIButton            *_passcodeButton;
    UIButton            *_cancelButton;
    UILabel             *_noFaceLabel;

    // State
    VZAuthPhase          _phase;
    NSInteger            _attemptCount;
    NSTimer             *_noFaceTimer;
    BOOL                 _authStarted;
}

// ── Factory ───────────────────────────────────────────────────────────────────

+ (instancetype)presentFromViewController:(UIViewController *)parent
                               completion:(nullable VZAuthCompletionBlock)completion {
    VZAuthViewController *vc = [[VZAuthViewController alloc] init];
    vc.completion            = completion;
    vc.showPasscodeFallback  = YES;
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle   = UIModalTransitionStyleCrossDissolve;
    [parent presentViewController:vc animated:YES completion:nil];
    return vc;
}

// ── Init ──────────────────────────────────────────────────────────────────────

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxAttempts          = kVZDefaultMaxAttempts;
        _showPasscodeFallback = YES;
        _phase                = VZAuthPhaseIdle;
        _attemptCount         = 0;
    }
    return self;
}

// ── View lifecycle ────────────────────────────────────────────────────────────

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self _buildUI];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!_authStarted) [self beginAuthentication];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self _teardown];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _previewLayer.frame = _previewContainer.bounds;
}

// ── UI construction ───────────────────────────────────────────────────────────

- (void)_buildUI {
    UIView *root = self.view;

    // Camera preview — fills the screen
    _previewContainer = [[UIView alloc] initWithFrame:root.bounds];
    _previewContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _previewContainer.backgroundColor  = UIColor.blackColor;
    [root addSubview:_previewContainer];

    // Dark gradient over preview so UI is readable
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame  = root.bounds;
    grad.colors = @[
        (__bridge id)[UIColor colorWithWhite:0 alpha:0.1].CGColor,
        (__bridge id)[UIColor colorWithWhite:0 alpha:0.55].CGColor,
    ];
    grad.locations = @[@0.4, @1.0];
    [root.layer addSublayer:grad];

    // Animated overlay — centered vertically at 40% of screen height
    CGFloat overlayW = MIN(root.bounds.size.width, 320);
    CGFloat overlayH = 300;
    CGRect overlayFrame = CGRectMake((root.bounds.size.width - overlayW) / 2,
                                     root.bounds.size.height * 0.25,
                                     overlayW, overlayH);
    _overlay = [[VZAuthOverlayView alloc] initWithFrame:overlayFrame];
    _overlay.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [root addSubview:_overlay];

    // "No face detected" warning
    _noFaceLabel                 = [[UILabel alloc] init];
    _noFaceLabel.font            = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    _noFaceLabel.textColor       = [UIColor colorWithWhite:1 alpha:0.7];
    _noFaceLabel.textAlignment   = NSTextAlignmentCenter;
    _noFaceLabel.text            = @"Move your face into view";
    _noFaceLabel.alpha           = 0;
    _noFaceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_noFaceLabel];

    // Passcode fallback
    _passcodeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_passcodeButton setTitle:@"Enter Passcode" forState:UIControlStateNormal];
    [_passcodeButton setTitleColor:[UIColor colorWithWhite:1 alpha:0.85] forState:UIControlStateNormal];
    _passcodeButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    _passcodeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_passcodeButton addTarget:self action:@selector(_passcodeTapped) forControlEvents:UIControlEventTouchUpInside];
    _passcodeButton.hidden = !_showPasscodeFallback;
    [root addSubview:_passcodeButton];

    // Cancel button (top-right)
    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [_cancelButton setTitleColor:[UIColor colorWithWhite:1 alpha:0.8] forState:UIControlStateNormal];
    _cancelButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_cancelButton addTarget:self action:@selector(cancelAuthentication) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_cancelButton];

    UILayoutGuide *safe = root.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_noFaceLabel.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [_noFaceLabel.topAnchor constraintEqualToAnchor:_overlay.bottomAnchor constant:16],

        [_passcodeButton.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [_passcodeButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-28],

        [_cancelButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_cancelButton.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
    ]];
}

// ── Auth flow ─────────────────────────────────────────────────────────────────

- (void)beginAuthentication {
    if (_authStarted || _phase == VZAuthPhaseDone) return;
    _authStarted = YES;
    _phase       = VZAuthPhaseRecognizing;

    // Check we actually have enrolled faces
    if ([VZFaceDatabase sharedDatabase].profiles.count == 0) {
        [self _finishWithResult:VZAuthResultFailure];
        return;
    }

    // Start camera
    _camera = [VZCameraController sharedController];
    __weak typeof(self) weak = self;
    _camera.stateBlock = ^(VZCameraState state, NSError *error) {
        [weak _cameraStateChanged:state error:error];
    };

    _recognizer = [[VZFaceRecognizer alloc] init];
    _recognizer.resultBlock = ^(VZFaceProfile *profile, float similarity,
                                 VNFaceObservation *obs, NSError *error) {
        [weak _recognitionResult:profile similarity:similarity observation:obs error:error];
    };

    _camera.sampleBufferBlock = ^(CMSampleBufferRef buf) {
        [weak->_recognizer processSampleBuffer:buf];
    };

    [_camera startSession];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _attachPreviewLayer];
        [self->_overlay startScanAnimation];
        [self _scheduleNoFaceWarning];
    });
}

- (void)_attachPreviewLayer {
    if (!_camera.previewLayer) return;
    _previewLayer = _camera.previewLayer;
    _previewLayer.frame = _previewContainer.bounds;
    [_previewContainer.layer insertSublayer:_previewLayer atIndex:0];
}

- (void)_cameraStateChanged:(VZCameraState)state error:(nullable NSError *)error {
    if (state == VZCameraStateRunning) {
        [_recognizer startRecognition];
        if (_previewLayer == nil) [self _attachPreviewLayer];
    } else if (state == VZCameraStateError) {
        // Camera failed — fall back to passcode
        [self _finishWithResult:VZAuthResultFallback];
    }
}

- (void)_recognitionResult:(nullable VZFaceProfile *)profile
                similarity:(float)similarity
               observation:(nullable VNFaceObservation *)obs
                     error:(nullable NSError *)error {
    if (_phase == VZAuthPhaseDone || _phase == VZAuthPhaseSuccess) return;

    if (error && error.code == VZErrorCodeNoFaceDetected) {
        // No face — show warning after delay
        return;  // noFaceTimer handles label
    }

    // Cancel no-face timer if a face is present
    [_noFaceTimer invalidate]; _noFaceTimer = nil;
    [UIView animateWithDuration:0.2 animations:^{ self->_noFaceLabel.alpha = 0; }];

    if (!profile) {
        // Known face not matched — continue scanning, increment attempts
        _attemptCount++;
        if (_attemptCount >= _maxAttempts) {
            [_overlay transitionToFailure];
            [self _scheduleTransition:VZAuthPhaseFailure delay:kVZFailureHoldDuration];
        }
        return;
    }

    // ── Recognized ────────────────────────────────────────────────────────────
    [_recognizer stopRecognition];
    _recognizedProfile = profile;

    VZPreferences *prefs = [VZPreferences sharedPreferences];
    if (prefs.anyLivenessEnabled) {
        [self _startLivenessChallenge];
    } else {
        [self _succeedAuthentication];
    }
}

// ── Liveness ──────────────────────────────────────────────────────────────────

- (void)_startLivenessChallenge {
    _phase = VZAuthPhaseLiveness;

    VZPreferences *prefs = [VZPreferences sharedPreferences];
    _livenessChallenge = [VZLivenessChallenge challengeFromPreferences:prefs.livenessRandomize];

    __weak typeof(self) weak = self;
    _livenessChallenge.progressBlock = ^(NSString *instruction, float progress) {
        [weak->_overlay setLivenessInstruction:instruction progress:progress];
    };
    _livenessChallenge.doneBlock = ^(BOOL success, NSError *error) {
        if (success) {
            [weak _succeedAuthentication];
        } else {
            [weak _failLiveness:error];
        }
    };

    // Wire liveness to the camera — feed face observations to the challenge
    __weak typeof(self) weakSelf2          = self;
    __weak VZLivenessChallenge *weakChallenge = _livenessChallenge;
    _camera.sampleBufferBlock = ^(CMSampleBufferRef buf) {
        CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(buf);
        if (!pb) { [weakChallenge processNoFace]; return; }
        [weakSelf2 _feedLivenessSampleBuffer:buf challenge:weakChallenge];
    };

    [_livenessChallenge start];
    [_overlay setLivenessInstruction:_livenessChallenge.currentInstruction
                            progress:_livenessChallenge.overallProgress];
}

- (void)_feedLivenessSampleBuffer:(CMSampleBufferRef)buf
                        challenge:(VZLivenessChallenge *)challenge {
    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(buf);
    if (!pb) return;
    CVPixelBufferRetain(pb);

    static dispatch_queue_t livenessQ;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        livenessQ = dispatch_queue_create("com.zeone.vis0g3.livenessVision", DISPATCH_QUEUE_SERIAL);
    });

    dispatch_async(livenessQ, ^{
        VNImageRequestHandler *h = [[VNImageRequestHandler alloc]
                                    initWithCVPixelBuffer:pb
                                             orientation:kCGImagePropertyOrientationLeftMirrored
                                                 options:@{}];
        CVPixelBufferRelease(pb);
        VNDetectFaceLandmarksRequest *req = [[VNDetectFaceLandmarksRequest alloc] init];
        if ([h performRequests:@[req] error:nil] && req.results.count > 0) {
            VNFaceObservation *obs = req.results.firstObject;
            dispatch_async(dispatch_get_main_queue(), ^{
                [challenge processFaceObservation:obs];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [challenge processNoFace];
            });
        }
    });
}

- (void)_failLiveness:(nullable NSError *)error {
    _phase = VZAuthPhaseFailure;
    _livenessChallenge = nil;
    [_overlay transitionToFailure];

    // Allow retry
    _attemptCount++;
    if (_attemptCount >= _maxAttempts) {
        [self _scheduleTransition:VZAuthPhaseFailure delay:kVZFailureHoldDuration];
    } else {
        __weak typeof(self) weakRetry = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVZFailureHoldDuration * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(self) s = weakRetry;
            if (!s || s->_phase == VZAuthPhaseDone) return;
            [s->_overlay transitionToScanning];
            s->_phase = VZAuthPhaseRecognizing;
            [s->_recognizer reset];
            [s->_recognizer startRecognition];
            __weak typeof(s) weakRetry2 = s;
            s->_camera.sampleBufferBlock = ^(CMSampleBufferRef buf) {
                [weakRetry2->_recognizer processSampleBuffer:buf];
            };
        });
    }
}

// ── Final states ──────────────────────────────────────────────────────────────

- (void)_succeedAuthentication {
    _phase = VZAuthPhaseSuccess;
    [_overlay transitionToSuccess];
    [_camera stopSession];
    [self _scheduleTransition:VZAuthPhaseSuccess delay:kVZSuccessHoldDuration];
}

- (void)_scheduleTransition:(VZAuthPhase)targetPhase delay:(NSTimeInterval)delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (targetPhase == VZAuthPhaseSuccess) {
            [self _finishWithResult:VZAuthResultSuccess];
        } else {
            [self _finishWithResult:VZAuthResultFailure];
        }
    });
}

- (void)_finishWithResult:(VZAuthResult)result {
    if (_phase == VZAuthPhaseDone) return;
    _phase = VZAuthPhaseDone;
    [self _teardown];
    VZAuthCompletionBlock block = _completion;
    if (block) {
        block(result);
    }
    if (self.presentingViewController) {
        [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    }
}

// ── Passcode / cancel ─────────────────────────────────────────────────────────

- (void)_passcodeTapped {
    [self _finishWithResult:VZAuthResultFallback];
}

- (void)cancelAuthentication {
    [self _finishWithResult:VZAuthResultCancelled];
}

// ── No-face warning timer ─────────────────────────────────────────────────────

- (void)_scheduleNoFaceWarning {
    [_noFaceTimer invalidate];
    _noFaceTimer = [NSTimer scheduledTimerWithTimeInterval:kVZNoFaceWarningDelay
                                                    target:self
                                                  selector:@selector(_showNoFaceWarning)
                                                  userInfo:nil
                                                   repeats:NO];
}

- (void)_showNoFaceWarning {
    [UIView animateWithDuration:0.3 animations:^{
        self->_noFaceLabel.alpha = 1.0;
    }];
    [self _scheduleNoFaceWarning];  // keep re-checking
}

// ── Cleanup ───────────────────────────────────────────────────────────────────

- (void)_teardown {
    [_noFaceTimer invalidate];
    _noFaceTimer = nil;
    [_livenessChallenge cancel];
    _livenessChallenge = nil;
    [_recognizer stopRecognition];
    _camera.sampleBufferBlock = nil;
    _camera.stateBlock        = nil;
    [_camera stopSession];
}

@end
