TARGET := iphoneos:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = VCAMNEXTPRO

VCAMNEXTPRO_FILES = $(shell find VCAMNEXTPRO -name '*.swift')
VCAMNEXTPRO_FRAMEWORKS = UIKit SwiftUI PhotosUI AVFoundation Network
VCAMNEXTPRO_CODESIGN_FLAGS = -SVCAMNEXTPRO/Entitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
