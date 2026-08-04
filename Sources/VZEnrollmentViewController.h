#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^VZEnrollmentCompletionBlock)(BOOL success, NSError *_Nullable error);

/// Guided multi-angle face enrollment flow.
///
/// Presents the front camera, walks the user through 4-5 pose captures
/// (center, left, right, up, down), collects feature vectors, then stores
/// the resulting profile in VZFaceDatabase.
///
/// Present modally from a UIViewController.
@interface VZEnrollmentViewController : UIViewController

/// Face name typed by the user, or "Face N" by default.
@property (nonatomic, copy, nullable) NSString *faceName;

/// If non-nil, the enrollment will replace this existing profile instead of
/// creating a new one.
@property (nonatomic, copy, nullable) NSString *replaceProfileID;

/// Called on the main queue when enrollment finishes or is cancelled.
@property (nonatomic, copy, nullable) VZEnrollmentCompletionBlock completion;

/// Convenience factory.
+ (instancetype)enrollmentControllerWithName:(nullable NSString *)name
                           replaceProfileID:(nullable NSString *)profileID
                                 completion:(nullable VZEnrollmentCompletionBlock)completion;

@end

NS_ASSUME_NONNULL_END
