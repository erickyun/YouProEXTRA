ARCHS = arm64
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = YouTube
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = HideChannelMembers
HideChannelMembers_FILES = Tweak.x
HideChannelMembers_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
HideChannelMembers_FRAMEWORKS = Foundation
include $(THEOS_MAKE_PATH)/tweak.mk
