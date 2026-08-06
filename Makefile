ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

# ── Main tweak: SpringBoard lock screen hooks ─────────────────────────────────

TWEAK_NAME = vis0g3

vis0g3_FILES = \
	Tweak.xm \
	Sources/VZPreferences.mm \
	Sources/VZFaceFeatureExtractor.mm \
	Sources/VZFaceDatabase.mm \
	Sources/VZFaceRecognizer.mm \
	Sources/VZLivenessChallenge.mm \
	Sources/VZCameraController.mm \
	Sources/VZAuthOverlayView.mm \
	Sources/VZAuthViewController.mm \
	Sources/VZEnrollmentViewController.mm

vis0g3_FRAMEWORKS = \
	UIKit \
	Foundation \
	AVFoundation \
	Vision \
	CoreImage \
	CoreGraphics \
	QuartzCore


vis0g3_LIBRARIES = substrate
vis0g3_CFLAGS    = -fobjc-arc -Wall -Wno-unused-variable
vis0g3_CCFLAGS   = -fobjc-arc -Wall -std=c++17
vis0g3_CFLAGS += -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

# ── Companion tweak: LAContext hooks in all UIKit apps ────────────────────────

TWEAK_NAME += vis0g3App

vis0g3App_FILES = \
	TweakApp.xm \
	Hooks/Authentication.xm \
	Sources/VZPreferences.mm \
	Sources/VZFaceFeatureExtractor.mm \
	Sources/VZFaceDatabase.mm \
	Sources/VZFaceRecognizer.mm \
	Sources/VZLivenessChallenge.mm \
	Sources/VZCameraController.mm \
	Sources/VZAuthOverlayView.mm \
	Sources/VZAuthViewController.mm \
	Sources/VZEnrollmentViewController.mm

vis0g3App_FRAMEWORKS = \
	UIKit \
	Foundation \
	AVFoundation \
	Vision \
	CoreImage \
	CoreGraphics \
	QuartzCore \
	LocalAuthentication

vis0g3App_LIBRARIES = substrate
vis0g3App_CFLAGS    = -fobjc-arc -Wall -Wno-unused-variable
vis0g3App_CCFLAGS   = -fobjc-arc -Wall -std=c++17

include $(THEOS_MAKE_PATH)/tweak.mk

# ── Preference bundle ─────────────────────────────────────────────────────────

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
