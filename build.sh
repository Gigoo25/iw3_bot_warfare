#!/bin/bash

# Bot Warfare IW3 Build Script
# This script compiles the mod files into z_svr_bots.iwd

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
MOD_NAME="z_svr_bots"
BUILD_DIR="build"
OUTPUT_DIR="output"
IWD_FILE="${MOD_NAME}.iwd"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bot Warfare IW3 Build Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Clean previous build
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}Cleaning previous build directory...${NC}"
    rm -rf "$BUILD_DIR"
fi

if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
fi

# Create build directory
echo -e "${YELLOW}Creating build directory...${NC}"
mkdir -p "$BUILD_DIR"

# Copy required files to build directory
echo -e "${YELLOW}Copying mod files...${NC}"

# Copy maps folder (contains all GSC scripts)
if [ -d "maps" ]; then
    cp -r maps "$BUILD_DIR/"
    echo -e "${GREEN}✓${NC} Copied maps folder"
else
    echo -e "${RED}✗${NC} maps folder not found!"
    exit 1
fi

# Copy scriptdata folder (contains waypoint data)
if [ -d "scriptdata" ]; then
    cp -r scriptdata "$BUILD_DIR/"
    echo -e "${GREEN}✓${NC} Copied scriptdata folder"
else
    echo -e "${RED}✗${NC} scriptdata folder not found!"
    exit 1
fi

# Copy scripts folder (contains CoD4x adapter scripts)
if [ -d "scripts" ]; then
    cp -r scripts "$BUILD_DIR/"
    echo -e "${GREEN}✓${NC} Copied scripts folder"
else
    echo -e "${RED}✗${NC} scripts folder not found!"
    exit 1
fi

# Create the IWD file (which is just a ZIP archive)
echo -e "${YELLOW}Creating IWD file...${NC}"
cd "$BUILD_DIR"

# Remove any .git folders or unnecessary files
find . -name ".git" -type d -exec rm -rf {} + 2>/dev/null
find . -name ".gitignore" -type f -delete 2>/dev/null
find . -name ".DS_Store" -type f -delete 2>/dev/null
find . -name "Thumbs.db" -type f -delete 2>/dev/null

# Create the IWD (ZIP) file
zip -r "../${OUTPUT_DIR}/${IWD_FILE}" * -x "*.git*" "*.DS_Store" "Thumbs.db"

if [ $? -eq 0 ]; then
    cd ..
    echo -e "${GREEN}✓${NC} Successfully created ${IWD_FILE}"
    
    # Show file size
    FILE_SIZE=$(ls -lh "${OUTPUT_DIR}/${IWD_FILE}" | awk '{print $5}')
    echo -e "${GREEN}✓${NC} File size: ${FILE_SIZE}"
    
    # Clean up build directory
    rm -rf "$BUILD_DIR"
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build completed successfully!${NC}"
    echo -e "${GREEN}Output file: ${OUTPUT_DIR}/${IWD_FILE}${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Installation instructions:${NC}"
    echo "1. Copy ${OUTPUT_DIR}/${IWD_FILE} to your CoD4x server folder"
    echo "2. Place it in: mods/mp_bots/"
    echo "3. Start your server with: +set fs_game \"mods/mp_bots\""
else
    cd ..
    echo -e "${RED}✗${NC} Failed to create IWD file!"
    exit 1
fi
