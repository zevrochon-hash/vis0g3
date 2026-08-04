#pragma once
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import "VZGlobals.h"

NS_ASSUME_NONNULL_BEGIN

/// Extracts a normalized geometric feature vector from a VNFaceObservation.
///
/// The vector encodes pairwise inter-landmark distances (normalized by the
/// inter-pupil distance) and relative landmark coordinates. It is robust to
/// moderate changes in scale, position, and mild lighting variation, but
/// intentionally NOT robust across different identities — which is the goal.
///
/// Dimension: kVZFeatureVectorDimension (30 floats).
@interface VZFaceFeatureExtractor : NSObject

/// Attempt to extract a feature vector from a face observation.
/// @param observation  Must have landmarks populated (VNDetectFaceLandmarksRequest).
/// @param outVector    Filled on success.
/// @return YES on success, NO if landmarks are insufficient.
+ (BOOL)extractFeatureVector:(VZFeatureVector *)outVector
             fromObservation:(VNFaceObservation *)observation;

/// Cosine similarity between two feature vectors.  Range: -1..1.
/// Values ≥ recognitionThreshold indicate the same identity.
+ (float)cosineSimilarityBetween:(const VZFeatureVector *)a
                             and:(const VZFeatureVector *)b;

/// Best-match similarity between an observed vector and a set of stored vectors.
/// Returns the highest cosine similarity found (or -1 if the array is empty).
+ (float)bestSimilarityForVector:(const VZFeatureVector *)observed
               againstStoredData:(NSArray<NSData *> *)storedVectors;

@end

NS_ASSUME_NONNULL_END
