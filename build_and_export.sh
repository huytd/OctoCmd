#!/bin/bash

# Build and Export Script for OctoCmd.app
# This script builds, archives, and exports the macOS app for distribution

set -e  # Exit on any error

# Configuration
PROJECT_NAME="OctoCmd"
SCHEME_NAME="OctoCmd"
WORKSPACE_DIR="$(pwd)"
BUILD_DIR="$WORKSPACE_DIR/build"
ARCHIVE_DIR="$WORKSPACE_DIR/archive"
EXPORT_DIR="$WORKSPACE_DIR/export"
ARCHIVE_PATH="$ARCHIVE_DIR/${PROJECT_NAME}.xcarchive"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to clean up previous builds
cleanup() {
    print_status "Cleaning up previous builds..."
    rm -rf "$BUILD_DIR"
    rm -rf "$ARCHIVE_DIR"
    rm -rf "$EXPORT_DIR"
    mkdir -p "$BUILD_DIR"
    mkdir -p "$ARCHIVE_DIR"
    mkdir -p "$EXPORT_DIR"
}

# Function to build and archive
build_and_archive() {
    print_status "Building and archiving $PROJECT_NAME..."
    
    xcodebuild -project "$PROJECT_NAME.xcodeproj" \
               -scheme "$SCHEME_NAME" \
               -configuration Release \
               -archivePath "$ARCHIVE_PATH" \
               archive \
               CODE_SIGN_IDENTITY="" \
               CODE_SIGNING_REQUIRED=NO \
               CODE_SIGNING_ALLOWED=NO \
               DEVELOPMENT_TEAM="" \
               -quiet
    
    if [ $? -eq 0 ]; then
        print_success "Archive created successfully at: $ARCHIVE_PATH"
    else
        print_error "Failed to create archive"
        exit 1
    fi
}

# Function to export the app
export_app() {
    print_status "Exporting .app from archive..."
    
    # Create export options plist for copy distribution
    cat > "$EXPORT_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <false/>
</dict>
</plist>
EOF
    
    xcodebuild -exportArchive \
               -archivePath "$ARCHIVE_PATH" \
               -exportPath "$EXPORT_DIR" \
               -exportOptionsPlist "$EXPORT_DIR/ExportOptions.plist" \
               -quiet
    
    if [ $? -eq 0 ]; then
        print_success "App exported successfully to: $EXPORT_DIR"
        
        # Find the exported app
        APP_PATH=$(find "$EXPORT_DIR" -name "*.app" -type d | head -n 1)
        if [ -n "$APP_PATH" ]; then
            print_success "Exported app location: $APP_PATH"
            
            # Get app size
            APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
            print_status "App size: $APP_SIZE"
            
            # Create a zip file for easy distribution
            print_status "Creating zip file for distribution..."
            cd "$EXPORT_DIR"
            APP_NAME=$(basename "$APP_PATH")
            ZIP_NAME="${APP_NAME%.app}_$(date +%Y%m%d_%H%M%S).zip"
            zip -r "$ZIP_NAME" "$APP_NAME" > /dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                print_success "Zip file created: $EXPORT_DIR/$ZIP_NAME"
                ZIP_SIZE=$(du -sh "$EXPORT_DIR/$ZIP_NAME" | cut -f1)
                print_status "Zip size: $ZIP_SIZE"
            else
                print_warning "Failed to create zip file, but app export was successful"
            fi
            
            cd "$WORKSPACE_DIR"
        else
            print_error "Could not find exported app"
            exit 1
        fi
    else
        print_error "Failed to export app"
        exit 1
    fi
}

# Function to display summary
show_summary() {
    echo ""
    echo "=========================================="
    print_success "BUILD AND EXPORT COMPLETED SUCCESSFULLY!"
    echo "=========================================="
    echo ""
    print_status "Build artifacts:"
    echo "  • Archive: $ARCHIVE_PATH"
    echo "  • Exported app: $EXPORT_DIR"
    echo ""
    
    # Find and display the final app and zip
    APP_PATH=$(find "$EXPORT_DIR" -name "*.app" -type d | head -n 1)
    ZIP_PATH=$(find "$EXPORT_DIR" -name "*.zip" | head -n 1)
    
    if [ -n "$APP_PATH" ]; then
        echo "  • App file: $APP_PATH"
    fi
    
    if [ -n "$ZIP_PATH" ]; then
        echo "  • Distribution zip: $ZIP_PATH"
    fi
    
    echo ""
    print_status "The app is ready for distribution!"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    print_status "BUILDING AND EXPORTING $PROJECT_NAME"
    echo "=========================================="
    echo ""
    
    # Check if we're in the right directory
    if [ ! -f "$PROJECT_NAME.xcodeproj/project.pbxproj" ]; then
        print_error "Could not find $PROJECT_NAME.xcodeproj in current directory"
        print_error "Please run this script from the project root directory"
        exit 1
    fi
    
    # Check if xcodebuild is available
    if ! command -v xcodebuild &> /dev/null; then
        print_error "xcodebuild command not found. Please install Xcode."
        exit 1
    fi
    
    cleanup
    build_and_archive
    export_app
    show_summary
}

# Run the main function
main "$@"