#pragma once
#import <Foundation/Foundation.h>
#import "VZGlobals.h"

NS_ASSUME_NONNULL_BEGIN

/// Represents one enrolled facial identity.
@interface VZFaceProfile : NSObject <NSSecureCoding>
@property (nonatomic, copy)   NSString        *name;
@property (nonatomic, strong) NSArray<NSData*> *featureVectors; // each: kVZFeatureVectorDimension floats
@property (nonatomic, strong) NSDate           *enrolledAt;
@property (nonatomic, copy)   NSString         *profileID;      // UUID string
@end

// ─────────────────────────────────────────────────────────────────────────────

/// Singleton that manages the on-device face enrollment database.
/// Stored as a plist in /var/mobile/Library/Preferences — no external uploads.
@interface VZFaceDatabase : NSObject

+ (instancetype)sharedDatabase;

/// All enrolled profiles, ordered by enrollment date.
@property (nonatomic, readonly) NSArray<VZFaceProfile *> *profiles;

/// YES if the maximum of 4 faces has been reached.
@property (nonatomic, readonly) BOOL isFull;

/// Enroll a new face with the given name and set of feature vectors.
/// Returns nil on success, or an NSError if the database is full or the write fails.
- (nullable NSError *)enrollFaceWithName:(NSString *)name
                          featureVectors:(NSArray<NSData *> *)vectors;

/// Remove an enrolled profile by ID.
- (BOOL)removeProfileWithID:(NSString *)profileID;

/// Replace the feature vectors for an existing profile (re-enroll).
- (BOOL)updateFeatureVectors:(NSArray<NSData *> *)vectors forProfileID:(NSString *)profileID;

/// Rename a profile.
- (BOOL)renameProfileWithID:(NSString *)profileID toName:(NSString *)newName;

/// Returns the profile whose stored vectors best match the given observed vector,
/// along with the best similarity score, or nil if no profile exceeds the threshold.
- (nullable VZFaceProfile *)bestMatchForFeatureVector:(const VZFeatureVector *)observed
                                         similarity:(float *)outSimilarity
                                          threshold:(float)threshold;

@end

NS_ASSUME_NONNULL_END
