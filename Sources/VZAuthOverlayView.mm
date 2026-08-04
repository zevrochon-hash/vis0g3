#import "VZAuthOverlayView.h"
#import <QuartzCore/QuartzCore.h>

// ── Geometry ──────────────────────────────────────────────────────────────────
static const CGFloat kGlyphSize      = 72.0;
static const CGFloat kRingWidth      = 3.5;
static const CGFloat kRingRadius     = 44.0;
static const CGFloat kScanLineHeight = 2.0;

// ── Colors ────────────────────────────────────────────────────────────────────
static UIColor *kColorPrimary(void)  { return [UIColor colorWithWhite:1 alpha:1]; }
static UIColor *kColorSuccess(void)  { return [UIColor colorWithRed:0.2 green:0.85 blue:0.4 alpha:1]; }
static UIColor *kColorFailure(void)  { return [UIColor colorWithRed:0.95 green:0.25 blue:0.2 alpha:1]; }

// ── Utilities ─────────────────────────────────────────────────────────────────
static CAShapeLayer *ringLayer(CGFloat radius, UIColor *color) {
    CAShapeLayer *l    = [CAShapeLayer layer];
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:
                          CGRectMake(-radius, -radius, radius*2, radius*2)];
    l.path        = path.CGPath;
    l.fillColor   = UIColor.clearColor.CGColor;
    l.strokeColor = color.CGColor;
    l.lineWidth   = kRingWidth;
    return l;
}

// ─────────────────────────────────────────────────────────────────────────────

@implementation VZAuthOverlayView {
    // Layers
    CAShapeLayer   *_faceGlyphLayer;
    CAShapeLayer   *_scanRingLayer;
    CAShapeLayer   *_scanRingProgress;
    CALayer        *_scanLineLayer;
    CAGradientLayer *_glowLayer;

    // UI
    UILabel        *_statusLabel;
    UILabel        *_instructionLabel;
    UIProgressView *_progressBar;

    VZAuthAnimationState _currentState;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        [self _buildUI];
        [self _buildLayers];
        _currentState = VZAuthAnimationStateIdle;
    }
    return self;
}

// ── Build ─────────────────────────────────────────────────────────────────────

- (void)_buildUI {
    // Status label (e.g. "Face ID" / "Move your face into view")
    _statusLabel                 = [[UILabel alloc] init];
    _statusLabel.font            = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _statusLabel.textColor       = UIColor.whiteColor;
    _statusLabel.textAlignment   = NSTextAlignmentCenter;
    _statusLabel.numberOfLines   = 2;
    _statusLabel.text            = @"vis0g3";
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_statusLabel];

    // Liveness instruction
    _instructionLabel              = [[UILabel alloc] init];
    _instructionLabel.font         = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _instructionLabel.textColor    = [UIColor colorWithWhite:1 alpha:0.8];
    _instructionLabel.textAlignment = NSTextAlignmentCenter;
    _instructionLabel.numberOfLines = 2;
    _instructionLabel.alpha        = 0;
    _instructionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_instructionLabel];

    // Progress bar for liveness steps
    _progressBar                   = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressBar.trackTintColor    = [UIColor colorWithWhite:1 alpha:0.25];
    _progressBar.progressTintColor = kColorSuccess();
    _progressBar.alpha             = 0;
    _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_progressBar];

    [NSLayoutConstraint activateConstraints:@[
        [_statusLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_statusLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:24],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],

        [_instructionLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_instructionLabel.bottomAnchor constraintEqualToAnchor:_progressBar.topAnchor constant:-12],
        [_instructionLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_instructionLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],

        [_progressBar.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_progressBar.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-32],
        [_progressBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:40],
        [_progressBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-40],
    ]];
}

- (void)_buildLayers {
    CGPoint center = CGPointMake(self.bounds.midX, self.bounds.midY);

    // Subtle glow behind glyph
    _glowLayer = [CAGradientLayer layer];
    _glowLayer.type = kCAGradientLayerRadial;
    _glowLayer.colors = @[
        (__bridge id)[UIColor colorWithWhite:1 alpha:0.12].CGColor,
        (__bridge id)[UIColor clearColor].CGColor
    ];
    _glowLayer.frame = CGRectMake(center.x - 70, center.y - 70, 140, 140);
    [self.layer addSublayer:_glowLayer];

    // Outer scanning ring (background track)
    _scanRingLayer = ringLayer(kRingRadius, [UIColor colorWithWhite:1 alpha:0.2]);
    _scanRingLayer.position = center;
    [self.layer addSublayer:_scanRingLayer];

    // Scanning ring progress (animated strokeEnd)
    _scanRingProgress = ringLayer(kRingRadius, kColorPrimary());
    _scanRingProgress.position     = center;
    _scanRingProgress.strokeStart  = 0;
    _scanRingProgress.strokeEnd    = 0;
    _scanRingProgress.transform    = CATransform3DMakeRotation(-M_PI_2, 0, 0, 1);
    [self.layer addSublayer:_scanRingProgress];

    // Scan line (horizontal sweep inside the ring)
    _scanLineLayer = [CALayer layer];
    _scanLineLayer.frame = CGRectMake(center.x - kRingRadius + 8,
                                      center.y - kScanLineHeight/2,
                                      (kRingRadius - 8) * 2,
                                      kScanLineHeight);
    _scanLineLayer.backgroundColor = [UIColor colorWithWhite:1 alpha:0.7].CGColor;
    _scanLineLayer.cornerRadius    = kScanLineHeight / 2;
    _scanLineLayer.opacity         = 0;
    [self.layer addSublayer:_scanLineLayer];

    // Face glyph — stylized face outline using bezier curves
    _faceGlyphLayer = [CAShapeLayer layer];
    UIBezierPath *glyphPath = [self _buildFaceGlyphPath];
    _faceGlyphLayer.path        = glyphPath.CGPath;
    _faceGlyphLayer.fillColor   = UIColor.clearColor.CGColor;
    _faceGlyphLayer.strokeColor = kColorPrimary().CGColor;
    _faceGlyphLayer.lineWidth   = 2.2;
    _faceGlyphLayer.lineCap     = kCALineCapRound;
    _faceGlyphLayer.lineJoin    = kCALineJoinRound;
    _faceGlyphLayer.position    = CGPointMake(center.x - kGlyphSize/2, center.y - kGlyphSize/2);
    [self.layer addSublayer:_faceGlyphLayer];
}

- (UIBezierPath *)_buildFaceGlyphPath {
    // Face ID-inspired outline: corners of a rounded face rectangle + eye dots + arc smile
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat w = kGlyphSize, h = kGlyphSize;
    CGFloat r = 14.0;  // corner radius
    CGFloat s = 12.0;  // corner segment length

    // Top-left corner
    [path moveToPoint:CGPointMake(s, 0)];
    [path addArcWithCenter:CGPointMake(r, r) radius:r startAngle:-M_PI_2 endAngle:M_PI clockwise:NO];
    [path addLineToPoint:CGPointMake(0, s)];

    // Bottom-left corner
    [path moveToPoint:CGPointMake(0, h-s)];
    [path addArcWithCenter:CGPointMake(r, h-r) radius:r startAngle:M_PI endAngle:M_PI_2 clockwise:NO];
    [path addLineToPoint:CGPointMake(s, h)];

    // Bottom-right corner
    [path moveToPoint:CGPointMake(w-s, h)];
    [path addArcWithCenter:CGPointMake(w-r, h-r) radius:r startAngle:M_PI_2 endAngle:0 clockwise:NO];
    [path addLineToPoint:CGPointMake(w, h-s)];

    // Top-right corner
    [path moveToPoint:CGPointMake(w, s)];
    [path addArcWithCenter:CGPointMake(w-r, r) radius:r startAngle:0 endAngle:-M_PI_2 clockwise:NO];
    [path addLineToPoint:CGPointMake(w-s, 0)];

    // Left eye
    [path addArcWithCenter:CGPointMake(w*0.33, h*0.38) radius:4.5 startAngle:0 endAngle:M_PI*2 clockwise:YES];
    // Right eye
    [path addArcWithCenter:CGPointMake(w*0.67, h*0.38) radius:4.5 startAngle:0 endAngle:M_PI*2 clockwise:YES];
    // Smile arc
    UIBezierPath *smile = [UIBezierPath bezierPath];
    [smile addArcWithCenter:CGPointMake(w*0.5, h*0.56) radius:w*0.18 startAngle:0 endAngle:M_PI clockwise:NO];
    [path appendPath:smile];

    return path;
}

// ── State transitions ─────────────────────────────────────────────────────────

- (void)setAnimationState:(VZAuthAnimationState)state {
    _animationState = state;
    _currentState   = state;
}

- (void)startScanAnimation {
    _animationState = VZAuthAnimationStateScanning;
    _faceGlyphLayer.strokeColor = kColorPrimary().CGColor;

    // Rotate scanning ring
    CABasicAnimation *rot = [CABasicAnimation animationWithKeyPath:@"transform.rotation"];
    rot.fromValue = @0;
    rot.toValue   = @(M_PI * 2);
    rot.duration  = 2.0;
    rot.repeatCount = HUGE_VALF;
    rot.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [_scanRingProgress addAnimation:rot forKey:@"rotation"];

    // Stroke end pulse
    CABasicAnimation *stroke = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    stroke.fromValue   = @0.0;
    stroke.toValue     = @0.75;
    stroke.duration    = 1.0;
    stroke.autoreverses = YES;
    stroke.repeatCount  = HUGE_VALF;
    stroke.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_scanRingProgress addAnimation:stroke forKey:@"strokePulse"];

    // Scan line sweep
    _scanLineLayer.opacity = 1;
    CABasicAnimation *sweep = [CABasicAnimation animationWithKeyPath:@"position.y"];
    CGFloat cy = self.bounds.midY;
    sweep.fromValue   = @(cy - kRingRadius + 6);
    sweep.toValue     = @(cy + kRingRadius - 6);
    sweep.duration    = 1.2;
    sweep.autoreverses = YES;
    sweep.repeatCount  = HUGE_VALF;
    sweep.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_scanLineLayer addAnimation:sweep forKey:@"sweep"];

    // Glyph pulse
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.fromValue   = @0.6;
    pulse.toValue     = @1.0;
    pulse.duration    = 0.9;
    pulse.autoreverses = YES;
    pulse.repeatCount  = HUGE_VALF;
    [_faceGlyphLayer addAnimation:pulse forKey:@"pulse"];

    _statusLabel.text = @"Look at vis0g3";
}

- (void)stopAnimations {
    [_scanRingProgress removeAllAnimations];
    [_scanLineLayer removeAllAnimations];
    [_faceGlyphLayer removeAllAnimations];
    _scanLineLayer.opacity = 0;
    _scanRingProgress.strokeEnd = 0;
    _statusLabel.text = @"vis0g3";
    [self _hideLiveness];
}

- (void)setLivenessInstruction:(nullable NSString *)instruction progress:(float)progress {
    _animationState = VZAuthAnimationStateLiveness;
    [UIView animateWithDuration:0.2 animations:^{
        self->_instructionLabel.alpha = instruction ? 1.0 : 0.0;
        self->_progressBar.alpha      = 1.0;
    }];
    _instructionLabel.text = instruction;
    [_progressBar setProgress:progress animated:YES];
    _statusLabel.text = @"Liveness check";
}

- (void)transitionToSuccess {
    _animationState = VZAuthAnimationStateSuccess;
    [_scanRingProgress removeAllAnimations];
    [_scanLineLayer removeAllAnimations];
    [_faceGlyphLayer removeAllAnimations];
    _scanLineLayer.opacity = 0;

    // Ring fills green
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.3];
    _scanRingProgress.strokeEnd    = 1.0;
    _scanRingProgress.strokeColor  = kColorSuccess().CGColor;
    _faceGlyphLayer.strokeColor    = kColorSuccess().CGColor;
    [CATransaction commit];

    _statusLabel.text = @"Authenticated";
    [self _hideLiveness];

    // Haptic
    UINotificationFeedbackGenerator *hap = [[UINotificationFeedbackGenerator alloc] init];
    [hap notificationOccurred:UINotificationFeedbackTypeSuccess];

    // Scale bounce
    _faceGlyphLayer.affineTransform = CGAffineTransformIdentity;
    CAKeyframeAnimation *bounce = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    bounce.values   = @[@1.0, @1.25, @0.95, @1.05, @1.0];
    bounce.keyTimes = @[@0, @0.35, @0.55, @0.75, @1.0];
    bounce.duration = 0.5;
    [_faceGlyphLayer addAnimation:bounce forKey:@"bounce"];
}

- (void)transitionToFailure {
    _animationState = VZAuthAnimationStateFailure;

    [CATransaction begin];
    [CATransaction setAnimationDuration:0.25];
    _scanRingProgress.strokeColor = kColorFailure().CGColor;
    _faceGlyphLayer.strokeColor   = kColorFailure().CGColor;
    [CATransaction commit];

    _statusLabel.text = @"Not recognized";

    UINotificationFeedbackGenerator *hap = [[UINotificationFeedbackGenerator alloc] init];
    [hap notificationOccurred:UINotificationFeedbackTypeError];

    // Shake
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"position.x"];
    CGFloat cx = _faceGlyphLayer.position.x;
    shake.values   = @[@(cx), @(cx+8), @(cx-8), @(cx+6), @(cx-6), @(cx+3), @(cx-3), @(cx)];
    shake.keyTimes = @[@0, @0.1, @0.25, @0.4, @0.55, @0.7, @0.85, @1.0];
    shake.duration = 0.45;
    [_faceGlyphLayer addAnimation:shake forKey:@"shake"];
}

- (void)transitionToScanning {
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.3];
    _scanRingProgress.strokeColor = kColorPrimary().CGColor;
    _faceGlyphLayer.strokeColor   = kColorPrimary().CGColor;
    [CATransaction commit];
    [self startScanAnimation];
}

- (void)_hideLiveness {
    [UIView animateWithDuration:0.2 animations:^{
        self->_instructionLabel.alpha = 0;
        self->_progressBar.alpha      = 0;
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Re-center layer-based elements when bounds change
    CGPoint center = CGPointMake(self.bounds.midX, self.bounds.midY);
    _scanRingLayer.position    = center;
    _scanRingProgress.position = center;
    _faceGlyphLayer.position   = CGPointMake(center.x - kGlyphSize/2, center.y - kGlyphSize/2);
    _glowLayer.frame           = CGRectMake(center.x - 70, center.y - 70, 140, 140);
    _scanLineLayer.frame = CGRectMake(center.x - kRingRadius + 8,
                                      center.y - kScanLineHeight/2,
                                      (kRingRadius - 8) * 2, kScanLineHeight);
}

@end
