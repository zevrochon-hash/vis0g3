#import "VZFaceFeatureExtractor.h"
#import <Vision/Vision.h>
#include <math.h>
#include <float.h>

// ── Landmark helper ───────────────────────────────────────────────────────────

static CGPoint centroidOfRegion(VNFaceLandmarkRegion2D * _Nullable region) {
    if (!region || region.pointCount == 0) return CGPointZero;
    CGFloat sx = 0, sy = 0;
    const CGPoint *points = region.normalizedPoints;
    for (NSUInteger i = 0; i < region.pointCount; i++) {
        sx += points[i].x;
        sy += points[i].y;
    }
    return CGPointMake(sx / region.pointCount, sy / region.pointCount);
}

static CGPoint midpoint(CGPoint a, CGPoint b) {
    return CGPointMake((a.x + b.x) * 0.5, (a.y + b.y) * 0.5);
}

static float distance(CGPoint a, CGPoint b) {
    float dx = (float)(a.x - b.x);
    float dy = (float)(a.y - b.y);
    return sqrtf(dx*dx + dy*dy);
}

// ── Feature extraction ────────────────────────────────────────────────────────

@implementation VZFaceFeatureExtractor

+ (BOOL)extractFeatureVector:(VZFeatureVector *)outVector
             fromObservation:(VNFaceObservation *)observation {

    VNFaceLandmarks2D *lm = observation.landmarks;
    if (!lm) return NO;

    // Key anchor points
    CGPoint leftPupil    = centroidOfRegion(lm.leftPupil);
    CGPoint rightPupil   = centroidOfRegion(lm.rightPupil);
    CGPoint leftEye      = centroidOfRegion(lm.leftEye);
    CGPoint rightEye     = centroidOfRegion(lm.rightEye);
    CGPoint nose         = centroidOfRegion(lm.nose);
    CGPoint noseCrest    = centroidOfRegion(lm.noseCrest);
    CGPoint outerLips    = centroidOfRegion(lm.outerLips);
    CGPoint innerLips    = centroidOfRegion(lm.innerLips);
    CGPoint leftBrow     = centroidOfRegion(lm.leftEyebrow);
    CGPoint rightBrow    = centroidOfRegion(lm.rightEyebrow);

    // Fallback: if no pupils, use eye centroids
    if (CGPointEqualToPoint(leftPupil, CGPointZero))  leftPupil  = leftEye;
    if (CGPointEqualToPoint(rightPupil, CGPointZero)) rightPupil = rightEye;

    // Inter-pupil distance — normalisation scale
    float ipd = distance(leftPupil, rightPupil);
    if (ipd < 0.01f) return NO;  // face too small or bad detection

    // Midpoint between pupils — normalisation origin
    CGPoint origin = midpoint(leftPupil, rightPupil);

    // Normalize a point relative to origin and scale
    auto norm = [&](CGPoint p) -> CGPoint {
        return CGPointMake((p.x - origin.x) / ipd, (p.y - origin.y) / ipd);
    };

    // Mouth corners from outerLips region
    CGPoint mouthLeft  = CGPointZero, mouthRight = CGPointZero;
    if (lm.outerLips && lm.outerLips.pointCount >= 7) {
        const CGPoint *pts = lm.outerLips.normalizedPoints;
        mouthLeft  = pts[0];
        mouthRight = pts[lm.outerLips.pointCount / 2];
    } else {
        mouthLeft = mouthRight = outerLips;
    }

    // Chin from faceContour bottom point
    CGPoint chin = CGPointZero;
    if (lm.faceContour && lm.faceContour.pointCount > 0) {
        const CGPoint *pts = lm.faceContour.normalizedPoints;
        NSUInteger count = lm.faceContour.pointCount;
        chin = pts[count / 2];  // bottom-center of contour
    }

    // 14 key points (normalized)
    CGPoint P[14];
    P[0]  = norm(leftPupil);
    P[1]  = norm(rightPupil);
    P[2]  = norm(leftEye);
    P[3]  = norm(rightEye);
    P[4]  = norm(nose);
    P[5]  = norm(noseCrest);
    P[6]  = norm(outerLips);
    P[7]  = norm(innerLips);
    P[8]  = norm(leftBrow);
    P[9]  = norm(rightBrow);
    P[10] = norm(mouthLeft);
    P[11] = norm(mouthRight);
    P[12] = norm(chin);
    P[13] = norm(midpoint(leftPupil, rightPupil));  // eye midpoint (should be near zero)

    // 30 pairwise distances between select pairs — dimensionally stable
    // Pairs chosen for good discriminative power (eye-nose, eye-mouth, nose-mouth, brow geometry)
    static const int pairsA[] = {0,0,0,0,0, 1,1,1,1, 2,2,2, 3,3, 4,4,4,4, 5,5, 6,6, 7, 8,8, 9, 10,10, 11, 12};
    static const int pairsB[] = {4,6,8,10,12, 5,7,9,11, 4,6,12, 5,7, 6,8,10,12, 6,12, 8,9, 9, 9,12, 12, 11,12, 12, 0};

    for (int i = 0; i < kVZFeatureVectorDimension; i++) {
        int a = pairsA[i], b = pairsB[i];
        outVector->values[i] = distance(P[a], P[b]);
    }

    // L2-normalize the vector for cosine similarity
    float norm2 = 0;
    for (int i = 0; i < kVZFeatureVectorDimension; i++) {
        norm2 += outVector->values[i] * outVector->values[i];
    }
    if (norm2 < FLT_EPSILON) return NO;
    float invNorm = 1.0f / sqrtf(norm2);
    for (int i = 0; i < kVZFeatureVectorDimension; i++) {
        outVector->values[i] *= invNorm;
    }

    return YES;
}

// ── Similarity ────────────────────────────────────────────────────────────────

+ (float)cosineSimilarityBetween:(const VZFeatureVector *)a
                             and:(const VZFeatureVector *)b {
    // Both vectors are already L2-normalized, so dot product == cosine similarity
    float dot = 0;
    for (int i = 0; i < kVZFeatureVectorDimension; i++) {
        dot += a->values[i] * b->values[i];
    }
    return dot;
}

+ (float)bestSimilarityForVector:(const VZFeatureVector *)observed
               againstStoredData:(NSArray<NSData *> *)storedVectors {
    float best = -1.0f;
    for (NSData *data in storedVectors) {
        VZFeatureVector stored;
        if (!VZFeatureVectorFromData(data, &stored)) continue;
        float sim = [self cosineSimilarityBetween:observed and:&stored];
        if (sim > best) best = sim;
    }
    return best;
}

@end
