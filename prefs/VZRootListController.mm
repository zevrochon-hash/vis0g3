#import "VZRootListController.h"
#import "VZFaceListController.h"
#import <notify.h>

// ── Private headers ───────────────────────────────────────────────────────────
// Preference framework is loaded by Settings; we only need the protocol.
@interface PSSpecifier (VZAdditions)
- (void)setProperty:(id)value forKey:(NSString *)key;
@end

static NSString * const kVZBundleID = @"com.zeone.vis0g3";
static NSString * const kVZPrefsChanged = @"com.zeone.vis0g3/preferences.changed";

@implementation VZRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// ── Preference change relay ───────────────────────────────────────────────────

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    notify_post(kVZPrefsChanged.UTF8String);
}

// ── Custom action: open face management ──────────────────────────────────────

- (void)openFaceManagement {
    VZFaceListController *faceList = [[VZFaceListController alloc] init];
    [self.navigationController pushViewController:faceList animated:YES];
}

// ── Custom action: reset all preferences to defaults ─────────────────────────

- (void)resetToDefaults {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Reset Settings"
                                            message:@"Reset all vis0g3 settings to defaults? Enrolled faces will not be removed."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *a) {
        NSDictionary *defaults = @{
            @"enabled":                    @YES,
            @"directHomeScreen":           @NO,
            @"screenFlashEnabled":         @YES,
            @"appAuthEnabled":             @YES,
            @"livenessHeadUpDown":         @NO,
            @"livenessHeadLeftRight":      @NO,
            @"livenessForeheadChin":       @NO,
            @"livenessLeftRightTurn":      @NO,
            @"livenessRandomize":          @NO,
            @"livenessMultipleMovements":  @NO,
            @"recognitionThreshold":       @0.82f,
        };
        for (NSString *key in defaults) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                     (__bridge CFPropertyListRef)defaults[key],
                                     (__bridge CFStringRef)kVZBundleID);
        }
        CFPreferencesAppSynchronize((__bridge CFStringRef)kVZBundleID);
        notify_post(kVZPrefsChanged.UTF8String);
        [self reloadSpecifiers];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
