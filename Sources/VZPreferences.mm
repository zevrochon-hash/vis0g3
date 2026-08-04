#import "VZPreferences.h"
#import "VZGlobals.h"
#import <notify.h>

@implementation VZPreferences {
    NSLock *_lock;
    // stored values
    BOOL _enabled;
    BOOL _directHomeScreen;
    BOOL _screenFlashEnabled;
    BOOL _appAuthEnabled;
    BOOL _livenessHeadUpDown;
    BOOL _livenessHeadLeftRight;
    BOOL _livenessForeheadChin;
    BOOL _livenessLeftRightTurn;
    BOOL _livenessRandomize;
    BOOL _livenessMultipleMovements;
    float _recognitionThreshold;
}

+ (instancetype)sharedPreferences {
    static VZPreferences *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[VZPreferences alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        [self reload];
    }
    return self;
}

- (void)reload {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kVZBundleID);
    NSDictionary *prefs = CFBridgingRelease(CFPreferencesCopyMultiple(
        NULL,
        (__bridge CFStringRef)kVZBundleID,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    ));

    [_lock lock];

    _enabled             = [self boolForKey:@"enabled"             inDict:prefs defaultValue:YES];
    _directHomeScreen    = [self boolForKey:@"directHomeScreen"    inDict:prefs defaultValue:NO];
    _screenFlashEnabled  = [self boolForKey:@"screenFlashEnabled"  inDict:prefs defaultValue:YES];
    _appAuthEnabled      = [self boolForKey:@"appAuthEnabled"      inDict:prefs defaultValue:YES];

    _livenessHeadUpDown      = [self boolForKey:@"livenessHeadUpDown"      inDict:prefs defaultValue:NO];
    _livenessHeadLeftRight   = [self boolForKey:@"livenessHeadLeftRight"   inDict:prefs defaultValue:NO];
    _livenessForeheadChin    = [self boolForKey:@"livenessForeheadChin"    inDict:prefs defaultValue:NO];
    _livenessLeftRightTurn   = [self boolForKey:@"livenessLeftRightTurn"   inDict:prefs defaultValue:NO];
    _livenessRandomize       = [self boolForKey:@"livenessRandomize"       inDict:prefs defaultValue:NO];
    _livenessMultipleMovements = [self boolForKey:@"livenessMultipleMovements" inDict:prefs defaultValue:NO];

    id rawThreshold = prefs[@"recognitionThreshold"];
    _recognitionThreshold = rawThreshold ? [rawThreshold floatValue] : 0.82f;
    _recognitionThreshold = MAX(0.5f, MIN(0.99f, _recognitionThreshold));

    [_lock unlock];
}

// ── Accessors (thread-safe) ───────────────────────────────────────────────────

#define VZ_BOOL_PROP(name) \
- (BOOL)name { [_lock lock]; BOOL v = _ ## name; [_lock unlock]; return v; }

VZ_BOOL_PROP(enabled)
VZ_BOOL_PROP(directHomeScreen)
VZ_BOOL_PROP(screenFlashEnabled)
VZ_BOOL_PROP(appAuthEnabled)
VZ_BOOL_PROP(livenessHeadUpDown)
VZ_BOOL_PROP(livenessHeadLeftRight)
VZ_BOOL_PROP(livenessForeheadChin)
VZ_BOOL_PROP(livenessLeftRightTurn)
VZ_BOOL_PROP(livenessRandomize)
VZ_BOOL_PROP(livenessMultipleMovements)

- (float)recognitionThreshold {
    [_lock lock];
    float v = _recognitionThreshold;
    [_lock unlock];
    return v;
}

- (BOOL)anyLivenessEnabled {
    [_lock lock];
    BOOL v = _livenessHeadUpDown || _livenessHeadLeftRight ||
             _livenessForeheadChin || _livenessLeftRightTurn;
    [_lock unlock];
    return v;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

- (BOOL)boolForKey:(NSString *)key inDict:(NSDictionary *)dict defaultValue:(BOOL)def {
    id val = dict[key];
    return val ? [val boolValue] : def;
}

@end
