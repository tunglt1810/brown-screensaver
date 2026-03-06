# Brown Screensaver Makefile
# Build screensaver for macOS

PRODUCT_NAME = BrownScreensaver
BUNDLE_NAME = $(PRODUCT_NAME).saver
INSTALL_DIR = $(HOME)/Library/Screen Savers

# Swift compiler settings
SWIFTC = swiftc
SWIFT_FLAGS = -O -whole-module-optimization -module-name $(PRODUCT_NAME)
FRAMEWORKS = -framework ScreenSaver -framework AVFoundation -framework AVKit -framework Cocoa

# Paths
BUILD_DIR = build
BUNDLE_DIR = $(BUILD_DIR)/$(BUNDLE_NAME)
CONTENTS_DIR = $(BUNDLE_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

.PHONY: all clean install uninstall reinstall

all: $(BUNDLE_DIR)

reinstall: uninstall clean all install

$(BUNDLE_DIR): BrownScreensaver.swift Info.plist
	@echo "Building $(PRODUCT_NAME)..."
	@mkdir -p "$(MACOS_DIR)"
	@mkdir -p "$(RESOURCES_DIR)"
	
	# Compile Swift code as a loadable bundle
	$(SWIFTC) $(SWIFT_FLAGS) $(FRAMEWORKS) \
		-Xlinker -bundle \
		-o "$(MACOS_DIR)/$(PRODUCT_NAME)" \
		BrownScreensaver.swift
	
	# Copy Info.plist
	cp Info.plist "$(CONTENTS_DIR)/"
	
	# Copy Resources
	cp -R Resources/* "$(RESOURCES_DIR)/"
	
	@echo "Build complete: $(BUNDLE_DIR)"

install: all
	@echo "Installing to $(INSTALL_DIR)..."
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@cp -R "$(BUNDLE_DIR)" "$(INSTALL_DIR)/"
	@echo "Installation complete!"
	@echo "Refreshing screensaver cache..."
	@-killall -9 legacyScreenSaver 2>/dev/null || true
	@-killall -9 ScreenSaverEngine 2>/dev/null || true
	@echo "You can now select '$(PRODUCT_NAME)' in System Settings > Screen Saver"

uninstall:
	@echo "Uninstalling $(BUNDLE_NAME)..."
	@rm -rf "$(INSTALL_DIR)/$(BUNDLE_NAME)"
	@echo "Uninstall complete!"

clean:
	@echo "Cleaning build directory..."
	@rm -rf $(BUILD_DIR)
	@echo "Clean complete!"

test: all
	@echo "Testing screensaver..."
	@open "$(BUNDLE_DIR)"
