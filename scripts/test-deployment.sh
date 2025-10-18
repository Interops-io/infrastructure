#!/bin/bash

# Test Infrastructure Deployment and Status Dashboard
echo "=== Infrastructure Deployment Test ==="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}❌ Missing .env file${NC}"
    echo "Creating sample .env file..."
    cat > .env << 'EOF'
# Infrastructure Domain (where all infrastructure runs)
INFRASTRUCTURE_DOMAIN=your-infrastructure-domain.com

# Database credentials
MYSQL_ROOT_PASSWORD=your_secure_root_password_here
MYSQL_DATABASE=laravel
MYSQL_USER=laravel
MYSQL_PASSWORD=your_secure_user_password_here

# Grafana credentials
GRAFANA_USER=admin
GRAFANA_PASSWORD=your_secure_grafana_password_here
EOF
    echo -e "${YELLOW}⚠️  Please update .env file with your actual credentials${NC}"
    exit 1
fi

echo -e "${GREEN}✅ .env file found${NC}"

# Start infrastructure
echo -e "\n${YELLOW}📦 Starting infrastructure...${NC}"
docker compose up -d

# Wait for services to be ready
echo -e "\n${YELLOW}⏳ Waiting for services to be ready...${NC}"
sleep 30

# Check service status
echo -e "\n${YELLOW}🔍 Checking service status...${NC}"
services=("traefik" "webhook" "mariadb" "prometheus" "grafana" "cadvisor" "node-exporter")

for service in "${services[@]}"; do
    # Use docker compose ps to check service status
    status=$(docker compose ps --services --filter "status=running" | grep "^$service$" 2>/dev/null)
    
    if [ -n "$status" ]; then
        echo -e "${GREEN}✅ $service is running${NC}"
    else
        # Check if service exists but is not running
        exists=$(docker compose ps --services | grep "^$service$" 2>/dev/null)
        if [ -n "$exists" ]; then
            service_status=$(docker compose ps "$service" --format "table {{.State}}" 2>/dev/null | tail -n +2)
            echo -e "${RED}❌ $service is $service_status${NC}"
        else
            echo -e "${RED}❌ $service service not found${NC}"
        fi
    fi
done

# Show URLs
echo -e "\n${GREEN}🌐 Your infrastructure is available at:${NC}"
DOMAIN=$(grep "^INFRASTRUCTURE_DOMAIN=" .env | cut -d '=' -f2 | tr -d '\r\n' | sed 's/[[:space:]]*$//')
echo "• Status Dashboard: https://status.$DOMAIN"
echo "• Monitoring: https://monitoring.$DOMAIN"  
echo "• Prometheus: https://prometheus.$DOMAIN"
echo "• Webhooks: https://webhook.$DOMAIN"
echo "• Traefik Dashboard: https://traefik.$DOMAIN"

# Test webhook endpoint
echo -e "\n${YELLOW}🔧 Testing webhook endpoint...${NC}"
if curl -s --connect-timeout 5 "https://webhook.$DOMAIN" > /dev/null; then
    echo -e "${GREEN}✅ Webhook endpoint is accessible${NC}"
else
    echo -e "${YELLOW}⚠️  Webhook endpoint not accessible (may require VPN)${NC}"
fi

echo -e "\n${GREEN}🎉 Deployment test complete!${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Update DNS records to point to this server"
echo "2. Configure your VPN to access infrastructure endpoints"  
echo "3. Set up webhooks in your Git repositories"
echo "4. Deploy your first project with: git push origin main"