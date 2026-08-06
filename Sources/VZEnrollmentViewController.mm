#import "VZEnrollmentViewController.h"
#import "VZCameraController.h"
#import "VZFaceRecognizer.h"
#import "VZFaceDatabase.h"
#import "VZGlobals.h"

// Enrollment stages with instructions and capture counts
typedef NS_ENUM(NSInteger, VZEnrollStage) {
    VZEnrollStageCenter = 0,
    VZEnrollStageLeft,
    VZEnrollStageRight,
    VZEnrollStageUp,
    VZEnrollStageDown,
    VZEnrollStageCount,
};

static NSString *instructionForStage(VZEnrollStage stage) {
    switch (stage) {
        case VZEnrollStageCenter: return @"Look straight at the camera";
        case VZEnrollStageLeft:   return @"Slowly turn your head left";
        case VZEnrollStageRight:  return @"Slowly turn your head right";
        case VZEnrollStageUp:     return @"Tilt your head slightly up";
        case VZEnrollStageDown:   return @"Tilt your head slightly down";
        default:                   return @"";
    }
}
// How many feature samples to capture per stage
static const NSInteger kSamplesPerStage = 2;

// ─────────────────────────────────────────────────────────────────────────────

@implementation VZEnrollmentViewController {
    // Camera
    VZCameraController  *_camera;
    VZFaceRecognizer    *_recognizer;
    AVCaptureVideoPreviewLayer *_previewLayer;

    // Collection state
    NSMutableArray<NSData *> *_collectedVectors;
    VZEnrollStage             _currentStage;
    NSInteger                 _samplesThisStage;
    BOOL                      _capturing;

    // UI
    UIView              *_previewContainer;
    UILabel             *_instructionLabel;
    UILabel             *_stageLabel;
    UIProgressView      *_progressBar;
    UIButton            *_cancelButton;
    UIButton            *_captureButton;
    UILabel             *_statusLabel;
    UIView              *_faceBracketView;
}

// ── Factory ───────────────────────────────────────────────────────────────────

+ (instancetype)enrollmentControllerWithName:(nullable NSString *)name
                           replaceProfileID:(nullable NSString *)profileID
                                 completion:(nullable VZEnrollmentCompletionBlock)completion {
    VZEnrollmentViewController *vc = [[VZEnrollmentViewController alloc] init];
    vc.faceName        = name;
    vc.replaceProfileID = profileID;
    vc.completion      = completion;
    return vc;
}

// ── Init ──────────────────────────────────────────────────────────────────────

- (instancetype)init {
    self = [super init];
    if (self) {
        _collectedVectors = [NSMutableArray array];
        _currentStage     = VZEnrollStageCenter;
        _samplesThisStage = 0;
    }
    return self;
}

// ── View lifecycle ────────────────────────────────────────────────────────────

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    [self _buildUI];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self _startCamera];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self _stopCamera];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _previewLayer.frame = _previewContainer.bounds;
}

// ── UI ────────────────────────────────────────────────────────────────────────

- (void)_buildUI {
    UIView *root = self.view;

    // Camera preview
    _previewContainer = [[UIView alloc] initWithFrame:root.bounds];
    _previewContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root addSubview:_previewContainer];

    // Face oval bracket
    _faceBracketView = [self _makeFaceBracket];
    [root addSubview:_faceBracketView];

    // Status + instructions
    _stageLabel                 = [[UILabel alloc] init];
    _stageLabel.font            = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _stageLabel.textColor       = [UIColor colorWithWhite:1 alpha:0.6];
    _stageLabel.textAlignment   = NSTextAlignmentCenter;
    _stageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_stageLabel];

    _instructionLabel              = [[UILabel alloc] init];
    _instructionLabel.font         = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    _instructionLabel.textColor    = UIColor.whiteColor;
    _instructionLabel.textAlignment = NSTextAlignmentCenter;
    _instructionLabel.numberOfLines = 2;
    _instructionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_instructionLabel];

    _progressBar                   = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressBar.trackTintColor    = [UIColor colorWithWhite:1 alpha:0.25];
    _progressBar.progressTintColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.4 alpha:1];
    _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_progressBar];

    _statusLabel                 = [[UILabel alloc] init];
    _statusLabel.font            = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    _statusLabel.textColor       = [UIColor colorWithWhite:1 alpha:0.75];
    _statusLabel.textAlignment   = NSTextAlignmentCenter;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_statusLabel];

    _captureButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_captureButton setTitle:@"Capture" forState:UIControlStateNormal];
    [_captureButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _captureButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
    _captureButton.layer.cornerRadius = 24;
    _captureButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _captureButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_captureButton addTarget:self action:@selector(_captureButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_captureButton];

    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [_cancelButton setTitleColor:[UIColor colorWithWhite:1 alpha:0.8] forState:UIControlStateNormal];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_cancelButton addTarget:self action:@selector(_cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_cancelButton];

    UILayoutGuide *safe = root.safeAreaLayoutGuide;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    CGFloat faceBracketCenterY = screenH * 0.38;

    [NSLayoutConstraint activateConstraints:@[
        [_stageLabel.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [_stageLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:24],

        [_instructionLabel.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [_instructionLabel.topAnchor constraintEqualToAnchor:_stageLabel.bottomAnchor constant:8],
        [_instructionLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [_instructionLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],

        [_faceBracketView.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [_faceBracketView.centerYAnchor constraintEqualToAnchor:root.topAnchor constant:faceBracketCenterY],

        [_statusLabel.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [_statusLabel.topAnchor constraintEqualToAnchor:_faceBracketView.bottomAnchor constant:20],

        [_progressBar.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [_progressBar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:40],
        [_progressBar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-40],
        [_progressBar.bottomAnchor constraintEqualToAnchor:_captureButton.topAnchor constant:-24],

        [_captureButton.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [_captureButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-48],
        [_captureButton.widthAnchor constraintEqualToConstant:160],
        [_captureButton.heightAnchor constraintEqualToConstant:48],

        [_cancelButton.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [_cancelButton.topAnchor constraintEqualToAnchor:_captureButton.bottomAnchor constant:12],
    ]];

    [self _updateUI];
}

- (UIView *)_makeFaceBracket {
    // Dashed oval guide to help user position their face
    CGFloat w = 180, h = 220;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    CAShapeLayer *ovalLayer = [CAShapeLayer layer];
    UIBezierPath *oval = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, w, h)];
    ovalLayer.path        = oval.CGPath;
    ovalLayer.fillColor   = UIColor.clearColor.CGColor;
    ovalLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.7].CGColor;
    ovalLayer.lineWidth   = 2.5;
    ovalLayer.lineDashPattern = @[@8, @6];
    ovalLayer.frame       = container.bounds;
    [container.layer addSublayer:ovalLayer];

    [NSLayoutConstraint activateConstraints:@[
        [container.widthAnchor constraintEqualToConstant:w],
        [container.heightAnchor constraintEqualToConstant:h],
    ]];
    return container;
}

// ── Camera ────────────────────────────────────────────────────────────────────

- (void)_startCamera {
    _camera = [VZCameraController sharedController];
    __weak __typeof__(self) weak = self;
    __weak __typeof__(self) weakSelf = self;

_camera.stateBlock = ^(VZCameraState state, NSError *err) {
    __strong __typeof__(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;

    if (state == VZCameraStateRunning) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof__(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            strongSelf->_previewLayer = strongSelf->_camera.previewLayer;
            if (strongSelf->_previewLayer) {
                strongSelf->_previewLayer.frame = strongSelf->_previewContainer.bounds;
                [strongSelf->_previewContainer.layer insertSublayer:strongSelf->_previewLayer atIndex:0];
            }
        });
    }
};
    [_camera startSession];
    _recognizer = [[VZFaceRecognizer alloc] init];
    // No resultBlock needed for enrollment — we use one-shot capture
}

- (void)_stopCamera {
    _camera.sampleBufferBlock = nil;
    _camera.stateBlock        = nil;
    [_camera stopSession];
    [_camera endScreenFlash];
}

// ── Capture ───────────────────────────────────────────────────────────────────

- (void)_captureButtonTapped {
    if (_capturing) return;
    _capturing = YES;
    _captureButton.enabled = NO;
    _statusLabel.text      = @"Capturing…";

    [_camera captureStillFrameWithCompletion:^(CVPixelBufferRef pixelBuffer, NSError *camError) {
        if (!pixelBuffer || camError) {
            [self _showError:camError ?: [NSError errorWithDomain:kVZErrorDomain
                                                             code:VZErrorCodeCameraUnavailable
                                                         userInfo:nil]];
            return;
        }
        [self->_recognizer extractFeatureVectorsFromPixelBuffer:pixelBuffer
                                                    completion:^(NSArray<NSData *> *vectors,
                                                                 VNFaceObservation *obs,
                                                                 NSError *err) {
            if (err || !vectors.count) {
                [self _showError:err ?: [NSError errorWithDomain:kVZErrorDomain
                                                            code:VZErrorCodeNoFaceDetected
                                                        userInfo:nil]];
                return;
            }
            [self _acceptCapture:vectors];
        }];
    }];
}

- (void)_acceptCapture:(NSArray<NSData *> *)vectors {
    [_collectedVectors addObjectsFromArray:vectors];
    _samplesThisStage++;

    // Haptic feedback
    UIImpactFeedbackGenerator *hap = [[UIImpactFeedbackGenerator alloc]
                                      initWithStyle:UIImpactFeedbackStyleLight];
    [hap impactOccurred];

    NSInteger samplesNeeded = (_currentStage == VZEnrollStageCenter) ? kSamplesPerStage : kSamplesPerStage;
    if (_samplesThisStage >= samplesNeeded) {
        // Advance stage
        _currentStage = (VZEnrollStage)((NSInteger)_currentStage + 1);
        _samplesThisStage = 0;

        if ((NSInteger)_currentStage >= VZEnrollStageCount) {
            [self _finalizeEnrollment];
        } else {
            _capturing = NO;
            _captureButton.enabled = YES;
            [self _updateUI];
        }
    } else {
        _capturing = NO;
        _captureButton.enabled = YES;
        _statusLabel.text = [NSString stringWithFormat:@"Good! One more from this angle."];
    }
}

- (void)_showError:(NSError *)error {
    _capturing = NO;
    _captureButton.enabled = YES;
    _statusLabel.text = error.localizedDescription ?: @"No face detected. Try again.";
    UINotificationFeedbackGenerator *hap = [[UINotificationFeedbackGenerator alloc] init];
    [hap notificationOccurred:UINotificationFeedbackTypeError];
}

// ── Finalize ──────────────────────────────────────────────────────────────────

- (void)_finalizeEnrollment {
    if (_collectedVectors.count < 2) {
        NSError *err = [NSError errorWithDomain:kVZErrorDomain
                                          code:VZErrorCodeEnrollmentFailed
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                     @"Insufficient face data captured."}];
        [self _completeWithSuccess:NO error:err];
        return;
    }

    NSString *name = _faceName.length ? _faceName :
                     [NSString stringWithFormat:@"Face %lu",
                      (unsigned long)[VZFaceDatabase sharedDatabase].profiles.count + 1];

    NSError *dbError;
    if (_replaceProfileID) {
        [[VZFaceDatabase sharedDatabase] updateFeatureVectors:[_collectedVectors copy]
                                               forProfileID:_replaceProfileID];
    } else {
        dbError = [[VZFaceDatabase sharedDatabase]
                   enrollFaceWithName:name
                       featureVectors:[_collectedVectors copy]];
    }

    [self _completeWithSuccess:(dbError == nil) error:dbError];
}

- (void)_completeWithSuccess:(BOOL)success error:(nullable NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _stopCamera];
        VZEnrollmentCompletionBlock block = self.completion;
        [self dismissViewControllerAnimated:YES completion:^{
            if (block) block(success, error);
        }];
    });
}

// ── Cancel ────────────────────────────────────────────────────────────────────

- (void)_cancelTapped {
    [self _stopCamera];
    [self dismissViewControllerAnimated:YES completion:^{
        if (self.completion) self.completion(NO, nil);
    }];
}

// ── UI update ─────────────────────────────────────────────────────────────────

- (void)_updateUI {
    NSInteger totalSamples   = VZEnrollStageCount * kSamplesPerStage;
    NSInteger capturedSoFar  = _collectedVectors.count;
    float     overallProgress = (float)capturedSoFar / (float)totalSamples;

    [UIView animateWithDuration:0.25 animations:^{
        [self->_progressBar setProgress:overallProgress animated:YES];
    }];

    _stageLabel.text       = [NSString stringWithFormat:@"Step %ld of %ld",
                               (long)(_currentStage + 1), (long)VZEnrollStageCount];
    _instructionLabel.text = instructionForStage(_currentStage);
    _statusLabel.text      = @"Position your face in the oval, then tap Capture.";
    _captureButton.enabled = YES;
}

@end
