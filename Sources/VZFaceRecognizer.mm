#import "VZFaceRecognizer.h"
#import "VZFaceFeatureExtractor.h"
#import "VZFaceDatabase.h"
#import "VZPreferences.h"
#import <Vision/Vision.h>

// Minimum face capture quality before we run recognition
static const float kVZMinFaceQuality = 0.2f;
// Minimum successful recognitions before reporting a match (reduces false positives)
static const NSInteger kVZConfirmationFrames = 2;

@implementation VZFaceRecognizer {
    BOOL _running;
    dispatch_queue_t _visionQueue;
    NSInteger _framesProcessed;
    NSInteger _consecutiveMatches;
    NSString *_lastMatchID;
    NSLock *_stateLock;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _visionQueue     = dispatch_queue_create("com.zeone.vis0g3.vision", DISPATCH_QUEUE_SERIAL);
        _stateLock       = [[NSLock alloc] init];
        _running         = NO;
        _framesProcessed = 0;
        _consecutiveMatches = 0;
    }
    return self;
}

- (NSInteger)framesProcessed {
    [_stateLock lock];
    NSInteger v = _framesProcessed;
    [_stateLock unlock];
    return v;
}

- (void)startRecognition {
    [_stateLock lock];
    _running = YES;
    [_stateLock unlock];
}

- (void)stopRecognition {
    [_stateLock lock];
    _running = NO;
    [_stateLock unlock];
}

- (void)reset {
    [_stateLock lock];
    _running = NO;
    _framesProcessed = 0;
    _consecutiveMatches = 0;
    _lastMatchID = nil;
    [_stateLock unlock];
}

// ── Live frame processing ─────────────────────────────────────────────────────

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    [_stateLock lock];
    BOOL running = _running;
    [_stateLock unlock];
    if (!running) return;

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;

    // Retain so it lives across the async dispatch
    CVPixelBufferRetain(pixelBuffer);

    dispatch_async(_visionQueue, ^{
        [self _runRecognitionOnPixelBuffer:pixelBuffer];
        CVPixelBufferRelease(pixelBuffer);
    });
}

- (void)_runRecognitionOnPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    [_stateLock lock];
    BOOL running = _running;
    [_stateLock unlock];
    if (!running) return;

    [_stateLock lock];
    _framesProcessed++;
    [_stateLock unlock];

    NSError *handlerError;
    NSDictionary *options = @{};
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc]
                                      initWithCVPixelBuffer:pixelBuffer
                                               orientation:kCGImagePropertyOrientationLeftMirrored
                                                   options:options];

    // Quality + landmarks in one pass
    VNDetectFaceCaptureQualityRequest *qualityReq = [[VNDetectFaceCaptureQualityRequest alloc] init];
    VNDetectFaceLandmarksRequest *landmarksReq    = [[VNDetectFaceLandmarksRequest alloc] init];

    if (![handler performRequests:@[qualityReq, landmarksReq] error:&handlerError]) {
        [self _reportError:handlerError];
        return;
    }

    NSArray<VNFaceObservation *> *landmarkResults = landmarksReq.results;
    if (landmarkResults.count == 0) {
        [self _reportError:[NSError errorWithDomain:kVZErrorDomain
                                              code:VZErrorCodeNoFaceDetected
                                          userInfo:@{NSLocalizedDescriptionKey:@"No face detected."}]];
        return;
    }
    if (landmarkResults.count > 1) {
        [self _reportError:[NSError errorWithDomain:kVZErrorDomain
                                              code:VZErrorCodeMultipleFaces
                                          userInfo:@{NSLocalizedDescriptionKey:@"Multiple faces detected."}]];
        return;
    }

    VNFaceObservation *faceObs = landmarkResults.firstObject;

    // Quality gate
    NSArray<VNFaceObservation *> *qualityResults = qualityReq.results;
    if (qualityResults.count > 0 && qualityResults.firstObject.faceCaptureQuality) {
        float q = qualityResults.firstObject.faceCaptureQuality.floatValue;
        if (q < kVZMinFaceQuality) {
            // Low quality — skip this frame silently
            return;
        }
    }

    // Extract feature vector
    VZFeatureVector observed;
    if (![VZFaceFeatureExtractor extractFeatureVector:&observed fromObservation:faceObs]) {
        return;  // insufficient landmarks
    }

    // Match against database
    float threshold = [VZPreferences sharedPreferences].recognitionThreshold;
    float similarity;
    VZFaceProfile *matched = [[VZFaceDatabase sharedDatabase]
                               bestMatchForFeatureVector:&observed
                                             similarity:&similarity
                                              threshold:threshold];

    [_stateLock lock];
    if (matched) {
        if ([matched.profileID isEqualToString:_lastMatchID]) {
            _consecutiveMatches++;
        } else {
            _consecutiveMatches = 1;
            _lastMatchID = matched.profileID;
        }
    } else {
        _consecutiveMatches = 0;
        _lastMatchID = nil;
    }
    NSInteger consecutive = _consecutiveMatches;
    [_stateLock unlock];

    // Only fire success after kVZConfirmationFrames consecutive matches
    if (matched && consecutive >= kVZConfirmationFrames) {
        VNFaceObservation *obsCapture = faceObs;
        VZFaceProfile *profileCapture = matched;
        float simCapture = similarity;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_resultBlock) {
                self->_resultBlock(profileCapture, simCapture, obsCapture, nil);
            }
        });
    } else if (!matched) {
        // Don't spam failure callbacks — only report if we've seen a clean miss
        if (consecutive == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_resultBlock) {
                    NSError *noMatch = [NSError errorWithDomain:kVZErrorDomain
                                                          code:VZErrorCodeRecognitionFailed
                                                      userInfo:@{NSLocalizedDescriptionKey:@"Face not recognized."}];
                    self->_resultBlock(nil, similarity, faceObs, noMatch);
                }
            });
        }
    }
}

// ── Still frame extraction (for enrollment) ───────────────────────────────────

- (void)extractFeatureVectorsFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                  completion:(void(^)(NSArray<NSData *> * _Nullable, VNFaceObservation *_Nullable, NSError *_Nullable))completion {
    CVPixelBufferRetain(pixelBuffer);
    dispatch_async(_visionQueue, ^{
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc]
                                          initWithCVPixelBuffer:pixelBuffer
                                                   orientation:kCGImagePropertyOrientationLeftMirrored
                                                       options:@{}];
        CVPixelBufferRelease(pixelBuffer);

        VNDetectFaceLandmarksRequest *req = [[VNDetectFaceLandmarksRequest alloc] init];
        NSError *err;
        if (![handler performRequests:@[req] error:&err]) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, err); });
            return;
        }
        if (req.results.count == 0) {
            NSError *noFace = [NSError errorWithDomain:kVZErrorDomain
                                                 code:VZErrorCodeNoFaceDetected
                                             userInfo:@{NSLocalizedDescriptionKey:@"No face detected."}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, noFace); });
            return;
        }
        VNFaceObservation *obs = req.results.firstObject;
        VZFeatureVector fv;
        if (![VZFaceFeatureExtractor extractFeatureVector:&fv fromObservation:obs]) {
            NSError *poor = [NSError errorWithDomain:kVZErrorDomain
                                               code:VZErrorCodePoorQuality
                                           userInfo:@{NSLocalizedDescriptionKey:@"Poor face quality for enrollment."}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, obs, poor); });
            return;
        }
        NSData *vecData = VZFeatureVectorToData(&fv);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(@[vecData], obs, nil); });
    });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

- (void)_reportError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_resultBlock) self->_resultBlock(nil, -1, nil, error);
    });
}

@end
