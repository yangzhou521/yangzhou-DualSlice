include ../__PREFIX__Build.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = __PREFIX__Prefs
__PREFIX__Prefs_FILES = $(wildcard *.m)
__PREFIX__Prefs_CFLAGS = -fobjc-arc -I../Sources
__PREFIX__Prefs_FRAMEWORKS = UIKit Foundation CoreFoundation
__PREFIX__Prefs_PRIVATE_FRAMEWORKS = Preferences
__PREFIX__Prefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
