#!/bin/bash

# Bot Warfare IW3 Development Script
# Unified script for building, deploying, testing, and analyzing bots

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SERVER_DIR="/home/rob/Cod4x Server"
MOD_DIR="mods/mp_bots"
DOCKER_COMPOSE_FILE="docker-compose.yml"
TEST_DURATION=30  # Fixed 30 seconds for bot connection
ANALYSIS_WAIT=${1:-60}  # Default 1 minute wait before analysis, can be overridden

# Record start time
START_TIME=$(date)
TOTAL_DURATION=$((TEST_DURATION + ANALYSIS_WAIT + 10))  # +10 for build/deploy time

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bot Warfare IW3 Development Workflow${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Session started at: ${START_TIME}${NC}"
echo -e "${BLUE}Estimated total duration: ${TOTAL_DURATION} seconds${NC}"
echo -e "${BLUE}Expected completion: $(date -d "+${TOTAL_DURATION} seconds")${NC}"
echo ""

# Function to show usage
show_usage() {
    echo -e "${YELLOW}Usage:${NC}"
    echo "  ./dev.sh [analysis_wait_seconds]"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  ./dev.sh          # Build, deploy, test 30s, wait 60s, then analyze"
    echo "  ./dev.sh 120      # Build, deploy, test 30s, wait 120s, then analyze"
    echo "  ./dev.sh 900      # Build, deploy, test 30s, wait 900s (15min), then analyze"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  analysis_wait_seconds: How long to wait before analyzing (default: 60)"
    echo "  Test duration is fixed at 30 seconds (sufficient for bot connection)"
}

# Check if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Validate analysis wait time
if ! [[ "$ANALYSIS_WAIT" =~ ^[0-9]+$ ]] || [ "$ANALYSIS_WAIT" -lt 10 ]; then
    echo -e "${RED}Error: Analysis wait time must be a number >= 10 seconds${NC}"
    show_usage
    exit 1
fi

echo -e "${BLUE}Test duration: ${TEST_DURATION} seconds (fixed)${NC}"
echo -e "${BLUE}Analysis wait: ${ANALYSIS_WAIT} seconds${NC}"
echo -e "${BLUE}Total analysis time: $((TEST_DURATION + ANALYSIS_WAIT)) seconds${NC}"
echo ""

# Step 1: Build
echo -e "${PURPLE}Step 1: Building mod...${NC}"
BUILD_START=$(date)
./build.sh
if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed! Aborting.${NC}"
    exit 1
fi
BUILD_END=$(date)
echo -e "${GREEN}✓ Build completed at: ${BUILD_END}${NC}"
echo ""

# Step 2: Deploy
echo -e "${PURPLE}Step 2: Deploying to server...${NC}"
DEPLOY_START=$(date)
./deploy.sh
if [ $? -ne 0 ]; then
    echo -e "${RED}Deployment failed! Aborting.${NC}"
    exit 1
fi
DEPLOY_END=$(date)
echo -e "${GREEN}✓ Deployment completed at: ${DEPLOY_END}${NC}"
echo ""

# Step 3: Wait for server to be ready
echo -e "${PURPLE}Step 3: Waiting for server to be ready...${NC}"
sleep 10
echo -e "${GREEN}✓ Server ready at: $(date)${NC}"
echo ""

# Step 4: Run test (fixed 30 seconds)
echo -e "${PURPLE}Step 4: Running bot test for ${TEST_DURATION} seconds...${NC}"
TEST_START=$(date)
echo -e "${YELLOW}Test started at: ${TEST_START}${NC}"
echo -e "${YELLOW}Test will end at: $(date -d "+${TEST_DURATION} seconds")${NC}"
echo ""

# Show progress bar
echo -n "Progress: ["
for i in {1..30}; do echo -n " "; done
echo -n "] 0%"
echo -ne "\r"

# Run test with progress bar
for i in $(seq 1 $TEST_DURATION); do
    # Update progress bar every second
    progress=$((i * 30 / TEST_DURATION))
    percentage=$((i * 100 / TEST_DURATION))
    echo -n "Progress: ["
    for j in $(seq 1 $progress); do echo -n "#"; done
    for j in $(seq $progress 29); do echo -n " "; done
    echo -n "] ${percentage}%"
    echo -ne "\r"
    sleep 1
done

TEST_END=$(date)
echo ""
echo -e "${GREEN}✓ Test completed at: ${TEST_END}${NC}"
echo ""

# Step 5: Wait before analysis
echo -e "${PURPLE}Step 5: Waiting ${ANALYSIS_WAIT} seconds before analysis...${NC}"
WAIT_START=$(date)
echo -e "${YELLOW}Wait started at: ${WAIT_START}${NC}"
echo -e "${YELLOW}Analysis will start at: $(date -d "+${ANALYSIS_WAIT} seconds")${NC}"
echo ""

# Show progress bar for analysis wait
echo -n "Waiting: ["
for i in {1..30}; do echo -n " "; done
echo -n "] 0%"
echo -ne "\r"

# Wait with progress bar
for i in $(seq 1 $ANALYSIS_WAIT); do
    # Update progress bar every 2 seconds for longer waits
    if [ $((i % 2)) -eq 0 ] || [ $i -eq $ANALYSIS_WAIT ]; then
        progress=$((i * 30 / ANALYSIS_WAIT))
        percentage=$((i * 100 / ANALYSIS_WAIT))
        echo -n "Waiting: ["
        for j in $(seq 1 $progress); do echo -n "#"; done
        for j in $(seq $progress 29); do echo -n " "; done
        echo -n "] ${percentage}%"
        echo -ne "\r"
    fi
    sleep 1
done

WAIT_END=$(date)
echo ""
echo -e "${GREEN}✓ Wait completed at: ${WAIT_END}${NC}"
echo ""

# Step 6: Analyze results
echo -e "${PURPLE}Step 6: Analyzing bot behavior...${NC}"
ANALYSIS_START=$(date)
echo -e "${YELLOW}Analysis started at: ${ANALYSIS_START}${NC}"
./analyze_bots.sh
ANALYSIS_END=$(date)
echo -e "${GREEN}✓ Analysis completed at: ${ANALYSIS_END}${NC}"

# Calculate total duration
END_TIME=$(date)
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Development cycle completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Timing Summary:${NC}"
echo -e "  Session started:    ${START_TIME}"
echo -e "  Session ended:      ${END_TIME}"
echo -e "  Build:              ${BUILD_START} → ${BUILD_END}"
echo -e "  Deploy:             ${DEPLOY_START} → ${DEPLOY_END}"
echo -e "  Test:               ${TEST_START} → ${TEST_END}"
echo -e "  Wait:               ${WAIT_START} → ${WAIT_END}"
echo -e "  Analysis:           ${ANALYSIS_START} → ${ANALYSIS_END}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review the analysis results above"
echo "2. Make improvements to the bot scripts"
echo "3. Run ./dev.sh again to test changes"
echo ""
echo -e "${BLUE}Quick commands:${NC}"
echo "  ./analyze_bots.sh --problems    # Show only problematic bots"
echo "  ./analyze_bots.sh --summary     # Show only summary"
echo "  ./analyze_bots.sh --recommendations  # Show only recommendations"
echo ""
echo -e "${YELLOW}Tips:${NC}"
echo "- Use shorter wait times (30-60s) for quick iterations"
echo "- Use longer wait times (120-300s) for comprehensive analysis"
echo "- 30 seconds is sufficient for bots to connect and start behaving"
