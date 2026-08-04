#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VZCameraState) {
    VZCameraStateIdle,
    VZCameraStateStarting,
    VZCameraStateRunning,
    VZCameraStateStopped,
    VZCameraStateError,
};

typedef void (^VZSampleBufferBlock)(CMSampleBufferRef sampleBuffer);
typedef void (^VZCameraStateBlock)(VZCameraState state, NSError *_Nullable error);

/// Manages the AVCaptureSession for vis0g3.
///
/// Only one session runs at a time. The session is torn down completely
/// when stopped — no lingering resources.
@interface VZCameraController : NSObject

+ (instancetype)sharedController;

@property (nonatomic, readonly) VZCameraState state;

/// Delivered on a private session queue (NOT main queue).
@property (nonatomic, copy, nullable) VZSampleBufferBlock sampleBufferBlock;

/// Delivered on main queue.
@property (nonatomic, copy, nullable) VZCameraStateBlock stateBlock;

/// A preview layer suitable for embedding in a view's layer tree.
/// Returns nil if the session is not running.
@property (nonatomic, readonly, nullable) AVCaptureVideoPreviewLayer *previewLayer;

/// Begin or resume the capture session.
- (void)startSession;

/// Gracefully stop and tear down the capture session.
- (void)stopSession;

/// Capture one still frame and call completion with the pixel buffer.
/// The completion is called on the main queue.
- (void)captureStillFrameWithCompletion:(void(^)(CVPixelBufferRef _Nullable pixelBuffer,
                                                 NSError *_Nullable error))completion;

/// Screen flash for low-light support.
- (void)beginScreenFlash;
- (void)endScreenFlash;

@end

NS_ASSUME_NONNULL_END
