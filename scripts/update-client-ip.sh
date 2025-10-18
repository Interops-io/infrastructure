#!/bin/bash

# Script to automatically update ALLOWED_CLIENT_IP in .env file
# Usage: ./scripts/update-client-ip.sh

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🔍 Detecting your current IP...${NC}"

# Get current IP
CURRENT_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || curl -s icanhazip.com 2>/dev/null)

if [ -z "$CURRENT_IP" ]; then
    echo "❌ Could not detect current IP"
    exit 1
fi

echo -e "${GREEN}📍 Current IP: $CURRENT_IP${NC}"

# Update .env file
ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ .env file not found"
    exit 1
fi

# Check if ALLOWED_CLIENT_IP already exists
if grep -q "^ALLOWED_CLIENT_IP=" "$ENV_FILE"; then
    # Update existing entry
    sed -i.backup "s/^ALLOWED_CLIENT_IP=.*/ALLOWED_CLIENT_IP=${CURRENT_IP}\/32/" "$ENV_FILE"
    echo -e "${GREEN}✅ Updated ALLOWED_CLIENT_IP in $ENV_FILE${NC}"
else
    # Add new entry
    echo "ALLOWED_CLIENT_IP=${CURRENT_IP}/32" >> "$ENV_FILE"
    echo -e "${GREEN}✅ Added ALLOWED_CLIENT_IP to $ENV_FILE${NC}"
fi

echo -e "${YELLOW}🔄 Restarting Traefik to apply changes...${NC}"
docker compose restart traefik

echo -e "${GREEN}🎉 Your infrastructure should now be accessible from IP: $CURRENT_IP${NC}"
echo -e "${GREEN}📱 Test: https://traefik.${INFRASTRUCTURE_DOMAIN:-localhost}${NC}"