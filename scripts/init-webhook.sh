#!/bin/sh

# Initialize webhook container with proper permissions
echo "Initializing webhook container..."

# Ensure log directory exists with proper permissions
mkdir -p /var/log/webhook
chmod 755 /var/log/webhook

# Create log file with proper permissions
touch /var/log/webhook/dispatcher.log
chmod 664 /var/log/webhook/dispatcher.log

echo "Log directory initialized successfully"

# Start the webhook service
exec /usr/local/bin/webhook -verbose -hooks=/etc/webhook/hooks.json -hotreload