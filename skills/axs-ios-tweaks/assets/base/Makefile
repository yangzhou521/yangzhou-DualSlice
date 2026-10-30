DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include __PREFIX__Build.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = __PREFIX__
__PREFIX___FILES = $(wildcard Hooks/*.xm Sources/*.m)
__PREFIX___CFLAGS = -fobjc-arc -I./Headers -I./Sources
__PREFIX___FRAMEWORKS = UIKit Foundation CoreFoundation
__PREFIX___LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

__SUBPROJECTS__
