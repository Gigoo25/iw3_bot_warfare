#!/bin/bash

# Bot Warfare IW3 Development Script
# Unified script for building, deploying, and testing bots

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

# Record start time
START_TIME=$(date)
TOTAL_DURATION=$((TEST_DURATION + 10))  # +10 for build/deploy time

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bot Warfare IW3 Development Workflow${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Session started at: ${START_TIME}${NC}"
echo -e "${BLUE}Estimated total duration: ${TOTAL_DURATION} seconds${NC}"
echo -e "${BLUE}Expected completion: $(date -d "+${TOTAL_DURATION} seconds")${NC}"
echo -e "${BLUE}Test duration: ${TEST_DURATION} seconds${NC}"
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
SERVER_READY_START=$(date)

# Wait for the server to start (using same logic as deploy.sh)
echo -e "${YELLOW}Checking server startup...${NC}"
MAX_WAIT=30
count=0
connected=false

while [ $count -lt $MAX_WAIT ]; do
    # Check for script compile errors first
    if docker compose -f "$SERVER_DIR/$DOCKER_COMPOSE_FILE" logs --tail=50 | grep -q "script compile error\|Sys_Error: script compile error"; then
        echo -e "\n${RED}Script compile error detected!${NC}"
        connected=false
        break
    fi
    
    # Check for successful server startup
    if docker compose -f "$SERVER_DIR/$DOCKER_COMPOSE_FILE" logs --tail=50 | grep -q "Steam: Server connected successfully"; then
        connected=true
        break
    fi
    echo -n "."
    count=$((count+1))
    sleep 1
done

echo ""
if [ "$connected" = true ]; then
    echo -e "${GREEN}✓ Server ready at: $(date)${NC}"
else
    echo -e "${RED}ERROR: Server failed to start correctly!${NC}"
    echo -e "${YELLOW}Check logs manually: docker compose -f \"$SERVER_DIR/$DOCKER_COMPOSE_FILE\" logs${NC}"
    echo -e "${RED}Deployment failed! Aborting.${NC}"
    exit 1
fi
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
echo -e "  Server ready:       ${SERVER_READY_START} → $(date -d "+$((count+1)) seconds" 2>/dev/null || echo "~$(date)")"
echo -e "  Test:               ${TEST_START} → ${TEST_END}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Make improvements to the bot scripts"
echo "2. Run ./dev.sh again to test changes"
echo ""
echo -e "${BLUE}Quick commands:${NC}"
echo "  ./dev.sh              # Build, deploy, and test"
echo "  docker compose -f \"$SERVER_DIR/$DOCKER_COMPOSE_FILE\" logs -f  # View live logs"
echo ""
echo -e "${YELLOW}Tips:${NC}"
echo "- 30 seconds is sufficient for bots to connect and start behaving"
echo "- Check server logs for any script errors or bot activity"
echo "- Use debug logging by setting bots_main_debug 2 in server.cfg"
