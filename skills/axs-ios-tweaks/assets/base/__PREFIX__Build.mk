DEBUG ?= 0
FINALPACKAGE ?= 1
ARCHS = arm64 arm64e

# Rootless and Roothide require iOS 15 or newer.
ifneq ($(filter rootless roothide,$(THEOS_PACKAGE_SCHEME)),)
TARGET = iphone:clang:__SDK_VERSION__:__JB_MIN_IOS__
else
TARGET = iphone:clang:__SDK_VERSION__:__MIN_IOS__
endif
