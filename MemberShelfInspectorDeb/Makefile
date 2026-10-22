ARCHS = arm64
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = YouTube
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = MemberShelfInspector
MemberShelfInspector_FILES = Tweak.x
MemberShelfInspector_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MemberShelfInspector_FRAMEWORKS = Foundation UIKit
include $(THEOS_MAKE_PATH)/tweak.mk
