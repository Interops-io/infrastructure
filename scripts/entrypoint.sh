#!/bin/bash
set -e

echo "🔧 Deployer container starting..."

# Ensure all scripts are executable
chmod +x /scripts/*.sh 2>/dev/null || true

# Ensure directories exist
mkdir -p /queue /projects /root/.ssh

# Set proper permissions
chmod 700 /root/.ssh 2>/dev/null || true

echo "✅ Deployer initialization complete"

# Execute the provided command
exec "$@"