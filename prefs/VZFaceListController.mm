#import "VZFaceListController.h"

// We dlopen the tweak dylib to access VZFaceDatabase from the prefs bundle.
// This avoids duplicating the storage code and keeps a single database.
// If the tweak isn't loaded (unlikely in Settings), we fall back gracefully.

#import <dlfcn.h>
#import <objc/runtime.h>

static NSString * const kVZBundleID      = @"com.zeone.vis0g3";
static NSString * const kVZFaceDBPath    = @"/var/mobile/Library/Preferences/com.zeone.vis0g3.faces.plist";
static NSString * const kVZPrefsChanged  = @"com.zeone.vis0g3/preferences.changed";

// ── Lightweight face profile for prefs (reads same plist as VZFaceDatabase) ──

static NSMutableArray<NSDictionary *> *loadFaceProfiles(void) {
    // Try to call VZFaceDatabase directly if it's loaded
    Class dbClass = NSClassFromString(@"VZFaceDatabase");
    if (dbClass && [dbClass respondsToSelector:NSSelectorFromString(@"sharedDatabase")]) {
        id db = [dbClass performSelector:NSSelectorFromString(@"sharedDatabase")];
        if (db) {
            NSArray *profiles = [db performSelector:NSSelectorFromString(@"profiles")];
            NSMutableArray *result = [NSMutableArray array];
            for (id p in profiles) {
                NSMutableDictionary *d = [NSMutableDictionary dictionary];
                SEL nameSel = NSSelectorFromString(@"name");
                SEL idSel   = NSSelectorFromString(@"profileID");
                SEL dateSel = NSSelectorFromString(@"enrolledAt");
                if ([p respondsToSelector:nameSel])  d[@"name"]      = [p performSelector:nameSel];
                if ([p respondsToSelector:idSel])    d[@"profileID"] = [p performSelector:idSel];
                if ([p respondsToSelector:dateSel])  d[@"enrolledAt"] = [p performSelector:dateSel];
                [result addObject:d];
            }
            return result;
        }
    }
    return [NSMutableArray array];
}

static void removeFaceProfile(NSString *profileID) {
    Class dbClass = NSClassFromString(@"VZFaceDatabase");
    if (!dbClass) return;
    id db = [dbClass performSelector:NSSelectorFromString(@"sharedDatabase")];
    if (!db) return;
    [db performSelector:NSSelectorFromString(@"removeProfileWithID:") withObject:profileID];
}

static void renameFaceProfile(NSString *profileID, NSString *newName) {
    Class dbClass = NSClassFromString(@"VZFaceDatabase");
    if (!dbClass) return;
    id db = [dbClass performSelector:NSSelectorFromString(@"sharedDatabase")];
    if (!db) return;
    [db performSelector:NSSelectorFromString(@"renameProfileWithID:toName:")
             withObject:profileID
             withObject:newName];
}

// ─────────────────────────────────────────────────────────────────────────────

static NSString * const kCellID    = @"VZFaceCell";
static NSString * const kAddCellID = @"VZAddCell";
static const NSInteger kSectionFaces = 0;
static const NSInteger kSectionAdd   = 1;

@implementation VZFaceListController {
    NSMutableArray<NSDictionary *> *_profiles;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Enrolled Faces";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCellID];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kAddCellID];
    [self _loadProfiles];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self _loadProfiles];
    [self.tableView reloadData];
}

- (void)_loadProfiles {
    _profiles = loadFaceProfiles();
}

// ── Table data source ─────────────────────────────────────────────────────────

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == kSectionFaces) return _profiles.count;
    // Add section: show row only when < 4 faces enrolled
    return (_profiles.count < 4) ? 1 : 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section == kSectionFaces) {
        return [NSString stringWithFormat:@"Enrolled (%lu / 4)", (unsigned long)_profiles.count];
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (section == kSectionFaces && _profiles.count == 0) {
        return @"No faces enrolled. Tap Add Face to enroll a face.";
    }
    if (section == kSectionAdd && _profiles.count >= 4) {
        return @"Maximum of 4 faces enrolled.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == kSectionAdd) {
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kAddCellID forIndexPath:ip];
        cell.textLabel.text      = @"Add Face…";
        cell.textLabel.textColor = self.view.tintColor;
        cell.accessoryType       = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kCellID forIndexPath:ip];
    NSDictionary *profile = _profiles[ip.row];
    cell.textLabel.text = profile[@"name"] ?: @"Unknown";
    NSDate *date        = profile[@"enrolledAt"];
    if (date) {
        static NSDateFormatter *df;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            df = [[NSDateFormatter alloc] init];
            df.dateStyle  = NSDateFormatterMediumStyle;
            df.timeStyle  = NSDateFormatterShortStyle;
        });
        cell.detailTextLabel.text = [NSString stringWithFormat:@"Enrolled %@", [df stringFromDate:date]];
    }
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    return cell;
}

- (UITableViewCellStyle)tableView:(UITableView *)tv styleForRowAtIndexPath:(NSIndexPath *)ip {
    return UITableViewCellStyleSubtitle;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == kSectionAdd) {
        [self _promptAddFace:nil replaceID:nil];
        return;
    }
    // Tap a face row — options
    NSDictionary *profile = _profiles[ip.row];
    NSString *profileID   = profile[@"profileID"];
    NSString *name        = profile[@"name"] ?: @"Face";
    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:name
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) {
        [self _promptRename:profileID currentName:name];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Re-enroll"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) {
        [self _promptAddFace:name replaceID:profileID];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Remove"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *a) {
        [self _confirmRemove:profileID name:name];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = tv;
        sheet.popoverPresentationController.sourceRect = [tv rectForRowAtIndexPath:ip];
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

// "Accessory button" = detail disclosure tap → go straight to re-enroll
- (void)tableView:(UITableView *)tv accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    NSDictionary *profile = _profiles[ip.row];
    [self _promptRename:profile[@"profileID"] currentName:profile[@"name"] ?: @"Face"];
}

// ── Swipe to delete ───────────────────────────────────────────────────────────

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == kSectionFaces;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tv editingStyleForRowAtIndexPath:(NSIndexPath *)ip {
    return (ip.section == kSectionFaces) ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style
forRowAtIndexPath:(NSIndexPath *)ip {
    if (style == UITableViewCellEditingStyleDelete && ip.section == kSectionFaces) {
        NSString *profileID = _profiles[ip.row][@"profileID"];
        NSString *name      = _profiles[ip.row][@"name"] ?: @"Face";
        [self _confirmRemove:profileID name:name];
    }
}

// ── Actions ───────────────────────────────────────────────────────────────────

- (void)_promptAddFace:(nullable NSString *)name replaceID:(nullable NSString *)replaceID {
    // Ask for a name, then launch the enrollment VC
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:replaceID ? @"Re-enroll Face" : @"Add Face"
                                            message:@"Enter a name for this face."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"e.g. My Face";
        tf.text        = name;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Continue"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) {
        NSString *chosenName = alert.textFields.firstObject.text;
        if (!chosenName.length) chosenName = name ?: @"Face";
        [self _launchEnrollmentWithName:chosenName replaceID:replaceID];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)_launchEnrollmentWithName:(NSString *)name replaceID:(nullable NSString *)replaceID {
    // Dynamically instantiate VZEnrollmentViewController from the tweak dylib
    Class enrollClass = NSClassFromString(@"VZEnrollmentViewController");
    if (!enrollClass) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"vis0g3"
                                                                     message:@"Enrollment is not available. Make sure vis0g3 is installed and SpringBoard is running."
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    // Use NSInvocation for a 3-argument class method selector
    SEL enrollSel = NSSelectorFromString(@"enrollmentControllerWithName:replaceProfileID:completion:");
    if (![enrollClass respondsToSelector:enrollSel]) return;
    NSMethodSignature *sig = [enrollClass methodSignatureForSelector:enrollSel];
    if (!sig) return;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target   = enrollClass;
    inv.selector = enrollSel;
    id nilBlock  = nil;
    [inv setArgument:&name      atIndex:2];
    [inv setArgument:&replaceID atIndex:3];
    [inv setArgument:&nilBlock  atIndex:4];
    [inv retainArguments];
    [inv invoke];
    __unsafe_unretained id rawEnrollVC;
    [inv getReturnValue:&rawEnrollVC];
    id enrollVC = rawEnrollVC;
    if (!enrollVC) return;

    // Set completion block via associated object trick (selector not available at compile time)
    __weak typeof(self) weak = self;
    void(^completion)(BOOL, NSError *) = ^(BOOL success, NSError *err) {
        [weak _loadProfiles];
        [weak.tableView reloadData];
        if (success) {
            UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"Enrolled"
                                                                        message:[NSString stringWithFormat:@""%@" has been enrolled.", name]
                                                                 preferredStyle:UIAlertControllerStyleAlert];
            [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [weak presentViewController:ok animated:YES completion:nil];
        }
    };

    // Set completion via KVC (VZEnrollmentViewController has a .completion property)
    [enrollVC setValue:[completion copy] forKey:@"completion"];

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:enrollVC];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)_promptRename:(NSString *)profileID currentName:(NSString *)currentName {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Rename Face"
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text        = currentName;
        tf.placeholder = @"Face name";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save"
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) {
        NSString *newName = alert.textFields.firstObject.text;
        if (newName.length) {
            renameFaceProfile(profileID, newName);
            [self _loadProfiles];
            [self.tableView reloadData];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)_confirmRemove:(NSString *)profileID name:(NSString *)name {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Remove "%@"?", name]
                                            message:@"This face will no longer be able to authenticate."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *a) {
        removeFaceProfile(profileID);
        [self _loadProfiles];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
