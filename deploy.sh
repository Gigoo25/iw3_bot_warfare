#!/bin/bash

# Bot Warfare IW3 Deploy Script
# This script builds the mod and deploys it to the CoD4x server for testing

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
# Containerized server (server/docker-compose.yml). The mod is mounted
# read-only from output/, so deploying = build + restart.
SERVER_DIR="$(cd "$(dirname "$0")" && pwd)/server"
DOCKER_COMPOSE_FILE="docker-compose.yml"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bot Warfare IW3 Deploy Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if server directory exists
if [ ! -d "$SERVER_DIR" ]; then
    echo -e "${RED}Error: Server directory not found: $SERVER_DIR${NC}"
    exit 1
fi

# Check if docker-compose file exists
if [ ! -f "$SERVER_DIR/$DOCKER_COMPOSE_FILE" ]; then
    echo -e "${RED}Error: docker-compose.yml not found in server directory${NC}"
    exit 1
fi

# Build the mod
echo -e "${YELLOW}Building mod...${NC}"
./build.sh

# Check if build was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Build failed, aborting deployment${NC}"
    exit 1
fi

# Check if server is running
echo -e "${YELLOW}Checking server status...${NC}"
if docker compose -f "$SERVER_DIR/$DOCKER_COMPOSE_FILE" ps | grep -q "Up"; then
    echo -e "${YELLOW}Server is running, restarting...${NC}"
    
    # Stop the server
    docker compose -f "$SERVER_DIR/$DOCKER_COMPOSE_FILE" down

    # Start the server
    docker compose -f "$SERVER_DIR/$DOCKER_COMPOSE_FILE" up -d
else
    echo -e "${YELLOW}Server is not running, starting...${NC}"
    docker compose -f "$SERVER_DIR/$DOCKER_COMPOSE_FILE" up -d
fi

# Wait for the server to start
echo -e "${YELLOW}Waiting for server to start...${NC}"
MAX_WAIT=30
count=0
connected=false

while [ $count -lt $MAX_WAIT ]; do
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
    echo -e "${GREEN}Server started successfully!${NC}"
    echo -e "${GREEN}Your mod has been deployed and is now running.${NC}"

else
    echo -e "${RED}Server may not have started correctly. Check logs manually:${NC}"
    echo -e "docker compose -f \"$SERVER_DIR/$DOCKER_COMPOSE_FILE\" logs"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment completed!${NC}"
echo -e "${GREEN}========================================${NC}"
