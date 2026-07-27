ARCHS = arm64
TARGET = iphone:clang:latest:14.0
THEOS_DEVICE_IP =

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CallVoiceFX

CallVoiceFX_FILES = Tweak.xm AudioEngineManager.m
CallVoiceFX_CFLAGS = -fobjc-arc
CallVoiceFX_FRAMEWORKS = UIKit AVFoundation AudioToolbox CoreTelephony
CallVoiceFX_PRIVATE_FRAMEWORKS = CoreTelephony

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences/CallVoiceFXPrefs.bundle
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard; killall -9 CommCenter"
