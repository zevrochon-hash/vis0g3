#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ── Package identity ──────────────────────────────────────────────────────────
static NSString * const kVZBundleID              = @"com.zeone.vis0g3";
static NSString * const kVZFaceDatabasePath      = @"/var/mobile/Library/Preferences/com.zeone.vis0g3.faces.plist";
static NSString * const kVZPrefsChangedNotification = @"com.zeone.vis0g3/preferences.changed";

// ── Recognition constants ─────────────────────────────────────────────────────
// Minimum cosine similarity to accept a match (0..1, higher = stricter)
static const float kVZDefaultRecognitionThreshold = 0.82f;
// Number of landmark feature samples stored per enrolled face
static const NSInteger kVZEnrollmentSampleCount   = 10;
// Maximum enrolled faces
static const NSInteger kVZMaxEnrolledFaces         = 4;

// ── Liveness constants ────────────────────────────────────────────────────────
// Minimum radians change to count as a completed head movement
static const float kVZLivenessYawThreshold   = 0.22f;
static const float kVZLivenessPitchThreshold = 0.18f;
// Maximum seconds to complete a liveness challenge
static const NSTimeInterval kVZLivenessTimeout = 15.0;

// ── Screen flash ──────────────────────────────────────────────────────────────
static const CGFloat kVZScreenFlashBrightness = 0.95f;
static const NSTimeInterval kVZFlashFadeDuration = 0.15;

// ── Face enrollment error domain ──────────────────────────────────────────────
static NSString * const kVZErrorDomain = @"com.zeone.vis0g3";

typedef NS_ENUM(NSInteger, VZErrorCode) {
    VZErrorCodeNoFaceDetected      = 1001,
    VZErrorCodeMultipleFaces       = 1002,
    VZErrorCodePoorQuality         = 1003,
    VZErrorCodeEnrollmentFailed    = 1004,
    VZErrorCodeRecognitionFailed   = 1005,
    VZErrorCodeCameraUnavailable   = 1006,
    VZErrorCodeLivenessTimeout     = 1007,
    VZErrorCodeLivenessFailed      = 1008,
    VZErrorCodeDatabaseFull        = 1009,
};

// ── Authentication result ─────────────────────────────────────────────────────
typedef NS_ENUM(NSInteger, VZAuthResult) {
    VZAuthResultSuccess,
    VZAuthResultFailure,
    VZAuthResultCancelled,
    VZAuthResultFallback,          // user tapped "Enter Passcode"
};

// ── Liveness challenge step types ─────────────────────────────────────────────
typedef NS_ENUM(NSInteger, VZLivenessStepType) {
    VZLivenessStepNone,
    VZLivenessStepLookUp,
    VZLivenessStepLookDown,
    VZLivenessStepTurnLeft,
    VZLivenessStepTurnRight,
};

// ── Face template ─────────────────────────────────────────────────────────────
// Each enrolled face stores multiple feature vectors (one per enrollment sample)
// Feature vector: 30 float values (pairwise distances between normalized landmarks)
static const NSInteger kVZFeatureVectorDimension = 30;

typedef struct {
    float values[30];
} VZFeatureVector;

static inline NSData *VZFeatureVectorToData(const VZFeatureVector *v) {
    return [NSData dataWithBytes:v->values length:sizeof(v->values)];
}

static inline BOOL VZFeatureVectorFromData(NSData *data, VZFeatureVector *outV) {
    if (data.length != sizeof(outV->values)) return NO;
    memcpy(outV->values, data.bytes, sizeof(outV->values));
    return YES;
}
