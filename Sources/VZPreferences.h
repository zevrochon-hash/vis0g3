#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thread-safe singleton that loads and caches vis0g3 preferences.
/// Updates are applied live via Darwin notification; no respring required.
@interface VZPreferences : NSObject

+ (instancetype)sharedPreferences;

// ── Master switch ─────────────────────────────────────────────────────────────
@property (nonatomic, readonly) BOOL enabled;

// ── Unlock behavior ───────────────────────────────────────────────────────────
@property (nonatomic, readonly) BOOL directHomeScreen;   // skip swipe-up after unlock

// ── Screen flash ──────────────────────────────────────────────────────────────
@property (nonatomic, readonly) BOOL screenFlashEnabled;

// ── App authentication ────────────────────────────────────────────────────────
@property (nonatomic, readonly) BOOL appAuthEnabled;     // hook LAContext

// ── Liveness toggles (each independent) ──────────────────────────────────────
@property (nonatomic, readonly) BOOL livenessHeadUpDown;
@property (nonatomic, readonly) BOOL livenessHeadLeftRight;
@property (nonatomic, readonly) BOOL livenessForeheadChin;
@property (nonatomic, readonly) BOOL livenessLeftRightTurn;
@property (nonatomic, readonly) BOOL livenessRandomize;
@property (nonatomic, readonly) BOOL livenessMultipleMovements;

// ── Recognition ──────────────────────────────────────────────────────────────
@property (nonatomic, readonly) float recognitionThreshold;  // 0..1

/// Whether ANY liveness toggle is enabled.
@property (nonatomic, readonly) BOOL anyLivenessEnabled;

/// Force a reload from disk (called on Darwin notification).
- (void)reload;

@end

NS_ASSUME_NONNULL_END
