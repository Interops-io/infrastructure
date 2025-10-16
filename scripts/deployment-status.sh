#!/bin/bash
# Deployment Status Script
# Shows current status of all deployed projects

set -e

echo "🚀 Infrastructure Deployment Status"
echo "=================================="
echo "Generated: $(date)"
echo ""

# Function to get container info
get_container_info() {
    local pattern=$1
    local project_name=$2
    
    echo "📦 $project_name"
    echo "-------------------"
    
    # Find containers matching pattern
    containers=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}" --filter "name=$pattern" 2>/dev/null || true)
    
    if [ -n "$containers" ] && [ "$containers" != "NAMES	STATUS	IMAGE	PORTS" ]; then
        echo "$containers"
        
        # Get image creation date and commit if available
        for container in $(docker ps --format "{{.Names}}" --filter "name=$pattern" 2>/dev/null || true); do
            image=$(docker inspect "$container" --format "{{.Config.Image}}" 2>/dev/null || echo "unknown")
            created=$(docker inspect "$image" --format "{{.Created}}" 2>/dev/null | cut -d'T' -f1 || echo "unknown")
            
            # Try to get git commit from image labels
            commit=$(docker inspect "$image" --format "{{.Config.Labels.git_commit}}" 2>/dev/null || echo "")
            if [ -z "$commit" ] || [ "$commit" = "<no value>" ]; then
                commit="unknown"
            fi
            
            echo "  Image built: $created"
            echo "  Git commit: $commit"
        done
    else
        echo "❌ No containers running"
    fi
    echo ""
}

# Check infrastructure services
echo "🏗️  Infrastructure Services"
echo "=========================="
get_container_info "traefik" "Traefik Reverse Proxy"
get_container_info "mariadb-shared" "Shared MariaDB"
# Redis is now per-project, not shared infrastructure
get_container_info "prometheus" "Prometheus Monitoring"
get_container_info "grafana" "Grafana Dashboards"
get_container_info "webhook" "Webhook Service"

echo "📱 Application Services"
echo "======================"

# Find all project containers (excluding infrastructure)
project_containers=$(docker ps --format "{{.Names}}" | grep -v -E "(traefik|mariadb-shared|prometheus|grafana|webhook|cadvisor|node-exporter)" || true)

if [ -n "$project_containers" ]; then
    for container in $project_containers; do
        # Extract project name (remove environment suffix)
        project=$(echo "$container" | sed 's/-prod$//' | sed 's/-staging$//' | sed 's/-dev$//')
        get_container_info "$container" "$project"
    done
else
    echo "❌ No application containers running"
    echo ""
fi

# Check for recent deployments
echo "📋 Recent Deployment Activity"
echo "============================="
if [ -f "/var/log/webhook/dispatcher.log" ]; then
    echo "Last 10 deployment events:"
    tail -n 10 /var/log/webhook/dispatcher.log | while read line; do
        echo "  $line"
    done
else
    echo "❌ No deployment logs found"
fi

echo ""
echo "🔗 Quick Links"
echo "=============="
echo "Traefik Dashboard: https://traefik.your-infrastructure-domain.com"
echo "Grafana Monitoring: https://monitoring.your-infrastructure-domain.com"
echo "Prometheus Metrics: https://prometheus.your-infrastructure-domain.com"