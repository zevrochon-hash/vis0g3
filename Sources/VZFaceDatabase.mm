#import "VZFaceDatabase.h"
#import "VZFaceFeatureExtractor.h"
#import "VZGlobals.h"

// ── VZFaceProfile ─────────────────────────────────────────────────────────────

@implementation VZFaceProfile

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _name           = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        _featureVectors = [coder decodeObjectOfClasses:
                           [NSSet setWithObjects:[NSArray class],[NSData class],nil]
                                                forKey:@"featureVectors"];
        _enrolledAt     = [coder decodeObjectOfClass:[NSDate class]   forKey:@"enrolledAt"];
        _profileID      = [coder decodeObjectOfClass:[NSString class]  forKey:@"profileID"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_name           forKey:@"name"];
    [coder encodeObject:_featureVectors forKey:@"featureVectors"];
    [coder encodeObject:_enrolledAt     forKey:@"enrolledAt"];
    [coder encodeObject:_profileID      forKey:@"profileID"];
}

@end

// ── VZFaceDatabase ────────────────────────────────────────────────────────────

@implementation VZFaceDatabase {
    NSMutableArray<VZFaceProfile *> *_profiles;
    NSString *_dbPath;
    dispatch_queue_t _queue;  // serial, protects _profiles
}

+ (instancetype)sharedDatabase {
    static VZFaceDatabase *shared;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ shared = [[VZFaceDatabase alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _dbPath   = kVZFaceDatabasePath;
        _queue    = dispatch_queue_create("com.zeone.vis0g3.facedb", DISPATCH_QUEUE_SERIAL);
        _profiles = [NSMutableArray array];
        [self _load];
    }
    return self;
}

// ── Persistence ───────────────────────────────────────────────────────────────

- (void)_load {
    dispatch_sync(_queue, ^{
        if (![[NSFileManager defaultManager] fileExistsAtPath:_dbPath]) return;
        NSError *err;
        NSData *data = [NSData dataWithContentsOfFile:_dbPath options:0 error:&err];
        if (!data) { NSLog(@"[vis0g3] DB load error: %@", err); return; }
        NSSet *allowed = [NSSet setWithArray:@[
            [NSArray class], [VZFaceProfile class], [NSString class],
            [NSData class], [NSDate class]
        ]];
        NSError *decodeErr;
        id decoded = [NSKeyedUnarchiver unarchivedObjectOfClasses:allowed
                                                        fromData:data
                                                           error:&decodeErr];
        if ([decoded isKindOfClass:[NSArray class]]) {
            _profiles = [(NSArray *)decoded mutableCopy];
        }
    });
}

- (BOOL)_save {
    // Called from _queue
    NSError *encErr;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[_profiles copy]
                                         requiringSecureCoding:YES
                                                         error:&encErr];
    if (!data) { NSLog(@"[vis0g3] DB encode error: %@", encErr); return NO; }
    NSError *writeErr;
    BOOL ok = [data writeToFile:_dbPath
                        options:NSDataWritingAtomic
                          error:&writeErr];
    if (!ok) NSLog(@"[vis0g3] DB write error: %@", writeErr);
    return ok;
}

// ── Public API ────────────────────────────────────────────────────────────────

- (NSArray<VZFaceProfile *> *)profiles {
    __block NSArray *copy;
    dispatch_sync(_queue, ^{ copy = [_profiles copy]; });
    return copy;
}

- (BOOL)isFull {
    __block BOOL full;
    dispatch_sync(_queue, ^{ full = _profiles.count >= (NSUInteger)kVZMaxEnrolledFaces; });
    return full;
}

- (nullable NSError *)enrollFaceWithName:(NSString *)name
                          featureVectors:(NSArray<NSData *> *)vectors {
    __block NSError *err = nil;
    dispatch_sync(_queue, ^{
        if (_profiles.count >= (NSUInteger)kVZMaxEnrolledFaces) {
            err = [NSError errorWithDomain:kVZErrorDomain
                                     code:VZErrorCodeDatabaseFull
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                @"Maximum of 4 faces already enrolled."}];
            return;
        }
        VZFaceProfile *profile  = [[VZFaceProfile alloc] init];
        profile.name            = name.length ? name : @"Face";
        profile.featureVectors  = [vectors copy];
        profile.enrolledAt      = [NSDate date];
        profile.profileID       = [[NSUUID UUID] UUIDString];
        [_profiles addObject:profile];
        [self _save];
    });
    return err;
}

- (BOOL)removeProfileWithID:(NSString *)profileID {
    __block BOOL found = NO;
    dispatch_sync(_queue, ^{
        for (NSUInteger i = 0; i < _profiles.count; i++) {
            if ([_profiles[i].profileID isEqualToString:profileID]) {
                [_profiles removeObjectAtIndex:i];
                found = YES;
                break;
            }
        }
        if (found) [self _save];
    });
    return found;
}

- (BOOL)updateFeatureVectors:(NSArray<NSData *> *)vectors forProfileID:(NSString *)profileID {
    __block BOOL found = NO;
    dispatch_sync(_queue, ^{
        for (VZFaceProfile *p in _profiles) {
            if ([p.profileID isEqualToString:profileID]) {
                p.featureVectors = [vectors copy];
                p.enrolledAt     = [NSDate date];
                found = YES;
                break;
            }
        }
        if (found) [self _save];
    });
    return found;
}

- (BOOL)renameProfileWithID:(NSString *)profileID toName:(NSString *)newName {
    __block BOOL found = NO;
    dispatch_sync(_queue, ^{
        for (VZFaceProfile *p in _profiles) {
            if ([p.profileID isEqualToString:profileID]) {
                p.name = newName;
                found  = YES;
                break;
            }
        }
        if (found) [self _save];
    });
    return found;
}

- (nullable VZFaceProfile *)bestMatchForFeatureVector:(const VZFeatureVector *)observed
                                         similarity:(float *)outSimilarity
                                          threshold:(float)threshold {
    __block VZFaceProfile *bestProfile = nil;
    __block float bestSim = -1.0f;

    dispatch_sync(_queue, ^{
        for (VZFaceProfile *profile in _profiles) {
            float sim = [VZFaceFeatureExtractor bestSimilarityForVector:observed
                                                      againstStoredData:profile.featureVectors];
            if (sim > bestSim) {
                bestSim     = sim;
                bestProfile = profile;
            }
        }
    });

    if (outSimilarity) *outSimilarity = bestSim;
    return (bestSim >= threshold) ? bestProfile : nil;
}

@end
