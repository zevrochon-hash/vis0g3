#import "VZCameraController.h"
#import "VZPreferences.h"
#import "VZGlobals.h"

@interface VZCameraController () <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

@implementation VZCameraController {
    AVCaptureSession            *_session;
    AVCaptureDeviceInput        *_deviceInput;
    AVCaptureVideoDataOutput    *_videoOutput;
    AVCaptureVideoPreviewLayer  *_previewLayer;
    dispatch_queue_t             _sessionQueue;
    dispatch_queue_t             _sampleQueue;
    VZCameraState                _state;
    NSLock                      *_stateLock;

    // Screen flash state
    CGFloat                      _savedBrightness;
    UIWindow                    *_flashWindow;

    // Still capture
    void (^_stillCapturePending)(CVPixelBufferRef, NSError *);
    BOOL _stillCaptureRequested;
}

+ (instancetype)sharedController {
    static VZCameraController *shared;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ shared = [[VZCameraController alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state        = VZCameraStateIdle;
        _stateLock    = [[NSLock alloc] init];
        _sessionQueue = dispatch_queue_create("com.zeone.vis0g3.session", DISPATCH_QUEUE_SERIAL);
        _sampleQueue  = dispatch_queue_create("com.zeone.vis0g3.samples", DISPATCH_QUEUE_SERIAL);

        // Monitor interruptions
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_sessionInterrupted:)
                                                     name:AVCaptureSessionWasInterruptedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_sessionResumed:)
                                                     name:AVCaptureSessionInterruptionEndedNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ── State helpers ─────────────────────────────────────────────────────────────

- (VZCameraState)state {
    [_stateLock lock];
    VZCameraState s = _state;
    [_stateLock unlock];
    return s;
}

- (void)_setState:(VZCameraState)state error:(nullable NSError *)error {
    [_stateLock lock];
    _state = state;
    [_stateLock unlock];
    if (_stateBlock) {
        VZCameraStateBlock block = _stateBlock;
        dispatch_async(dispatch_get_main_queue(), ^{ block(state, error); });
    }
}

// ── Session management ────────────────────────────────────────────────────────

- (void)startSession {
    [self _setState:VZCameraStateStarting error:nil];
    dispatch_async(_sessionQueue, ^{
        [self _configureAndStart];
    });
}

- (void)_configureAndStart {
    // Authorization
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted) {
        NSError *err = [NSError errorWithDomain:kVZErrorDomain
                                          code:VZErrorCodeCameraUnavailable
                                      userInfo:@{NSLocalizedDescriptionKey:@"Camera access denied."}];
        [self _setState:VZCameraStateError error:err];
        return;
    }
    if (status == AVAuthorizationStatusNotDetermined) {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] != AVAuthorizationStatusAuthorized) {
            NSError *err = [NSError errorWithDomain:kVZErrorDomain
                                              code:VZErrorCodeCameraUnavailable
                                          userInfo:@{NSLocalizedDescriptionKey:@"Camera access not granted."}];
            [self _setState:VZCameraStateError error:err];
            return;
        }
    }

    // Front camera
    AVCaptureDevice *frontCamera = nil;
    if (@available(iOS 10.0, *)) {
        AVCaptureDeviceDiscoverySession *ds = [AVCaptureDeviceDiscoverySession
            discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
                                  mediaType:AVMediaTypeVideo
                                   position:AVCaptureDevicePositionFront];
        frontCamera = ds.devices.firstObject;
    } 
    
    if (!frontCamera) {
        NSError *err = [NSError errorWithDomain:kVZErrorDomain
                                          code:VZErrorCodeCameraUnavailable
                                      userInfo:@{NSLocalizedDescriptionKey:@"Front camera not found."}];
        [self _setState:VZCameraStateError error:err];
        return;
    }

    // Session
    _session = [[AVCaptureSession alloc] init];
    [_session beginConfiguration];
    _session.sessionPreset = AVCaptureSessionPreset1280x720;

    NSError *inputError;
    _deviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:frontCamera error:&inputError];
    if (!_deviceInput || inputError) {
        [self _setState:VZCameraStateError error:inputError];
        _session = nil;
        return;
    }
    if ([_session canAddInput:_deviceInput]) [_session addInput:_deviceInput];

    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    _videoOutput.videoSettings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    [_videoOutput setSampleBufferDelegate:self queue:_sampleQueue];
    if ([_session canAddOutput:_videoOutput]) [_session addOutput:_videoOutput];

    // Preview layer
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self->_session];
        self->_previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    });

    [_session commitConfiguration];
    [_session startRunning];
    [self _setState:VZCameraStateRunning error:nil];

    // Optional screen flash
    if ([VZPreferences sharedPreferences].screenFlashEnabled) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self beginScreenFlash]; });
    }
}

- (void)stopSession {
    dispatch_async(_sessionQueue, ^{
        if (self->_session.isRunning) [self->_session stopRunning];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self endScreenFlash];
            self->_previewLayer = nil;
        });

        [self->_videoOutput setSampleBufferDelegate:nil queue:NULL];
        self->_videoOutput  = nil;
        self->_deviceInput  = nil;
        self->_session      = nil;
        [self _setState:VZCameraStateStopped error:nil];
    });
}

- (AVCaptureVideoPreviewLayer *)previewLayer { return _previewLayer; }

// ── Still capture ─────────────────────────────────────────────────────────────

- (void)captureStillFrameWithCompletion:(void(^)(CVPixelBufferRef, NSError *))completion {
    [_stateLock lock];
    _stillCapturePending   = completion;
    _stillCaptureRequested = YES;
    [_stateLock unlock];
}

// ── AVCaptureVideoDataOutputSampleBufferDelegate ──────────────────────────────

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {

    // Check for pending still capture first
    [_stateLock lock];
    BOOL captureRequested = _stillCaptureRequested;
    void (^pendingCompletion)(CVPixelBufferRef, NSError *) = _stillCapturePending;
    if (captureRequested) {
        _stillCaptureRequested = NO;
        _stillCapturePending   = nil;
    }
    [_stateLock unlock];

    if (captureRequested && pendingCompletion) {
        CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (pb) {
            CVPixelBufferRetain(pb);
            dispatch_async(dispatch_get_main_queue(), ^{
                pendingCompletion(pb, nil);
                CVPixelBufferRelease(pb);
            });
        }
    }

    // Forward to registered block
    VZSampleBufferBlock block = _sampleBufferBlock;
    if (block) block(sampleBuffer);
}

- (void)captureOutput:(AVCaptureOutput *)output
  didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    // Dropped frames are expected under load; no action needed
}

// ── Interruptions ─────────────────────────────────────────────────────────────

- (void)_sessionInterrupted:(NSNotification *)note {
    [self _setState:VZCameraStateError error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{ [self endScreenFlash]; });
}

- (void)_sessionResumed:(NSNotification *)note {
    if (self.state == VZCameraStateError) {
        [self _setState:VZCameraStateRunning error:nil];
    }
}

// ── Screen flash ──────────────────────────────────────────────────────────────

- (void)beginScreenFlash {
    if (_flashWindow) return;
    _savedBrightness = [UIScreen mainScreen].brightness;

    // iOS 13+ requires a windowScene
    UIWindowScene *scene = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] &&
                s.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)s;
                break;
            }
        }
    }

    if (@available(iOS 13.0, *)) {
        if (scene) {
            _flashWindow = [[UIWindow alloc] initWithWindowScene:scene];
        }
    }
    if (!_flashWindow) {
        _flashWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }

    _flashWindow.backgroundColor = [UIColor whiteColor];
    _flashWindow.windowLevel     = UIWindowLevelStatusBar + 50;
    _flashWindow.alpha           = 0;
    _flashWindow.hidden          = NO;
    [UIView animateWithDuration:kVZFlashFadeDuration animations:^{
        self->_flashWindow.alpha = 0.8f;
    }];
    [[UIScreen mainScreen] setBrightness:kVZScreenFlashBrightness];
}

- (void)endScreenFlash {
    if (!_flashWindow) return;
    [[UIScreen mainScreen] setBrightness:_savedBrightness];
    UIWindow *fw = _flashWindow;
    _flashWindow = nil;
    [UIView animateWithDuration:kVZFlashFadeDuration animations:^{
        fw.alpha = 0;
    } completion:^(BOOL done) {
        fw.hidden = YES;
    }];
}

@end
