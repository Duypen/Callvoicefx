ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CallVoiceFXPrefs

CallVoiceFXPrefs_FILES = CVFRootListController.m CVFMusicPickerController.m
CallVoiceFXPrefs_INSTALL_PATH = /Library/PreferenceBundles
CallVoiceFXPrefs_FRAMEWORKS = UIKit
CallVoiceFXPrefs_PRIVATE_FRAMEWORKS = Preferences
CallVoiceFXPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
