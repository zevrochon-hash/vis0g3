#pragma once
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <AVFoundation/AVFoundation.h>
#import "VZGlobals.h"
#import "VZFaceDatabase.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^VZRecognitionResultBlock)(VZFaceProfile *_Nullable matchedProfile,
                                        float similarity,
                                        VNFaceObservation *_Nullable observation,
                                        NSError *_Nullable error);

/// Processes AVCaptureVideoDataOutput sample buffers through Vision,
/// extracts feature vectors, and matches them against the enrolled database.
///
/// Results are delivered on the main queue.
@interface VZFaceRecognizer : NSObject

@property (nonatomic, copy, nullable) VZRecognitionResultBlock resultBlock;

/// Number of frames processed since last reset.
@property (nonatomic, readonly) NSInteger framesProcessed;

/// Start/stop recognition passes.
- (void)startRecognition;
- (void)stopRecognition;
- (void)reset;

/// Feed a sample buffer from AVCaptureVideoDataOutput.
- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer;

/// Extract and return feature vectors from a still pixel buffer (for enrollment).
/// Calls completion on the main queue.
- (void)extractFeatureVectorsFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                  completion:(void(^)(NSArray<NSData *> * _Nullable vectors,
                                                      VNFaceObservation *_Nullable obs,
                                                      NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
