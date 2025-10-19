#!/bin/sh

# Lightweight webhook handler - validates and queues deployment requests
# Actual deployment is handled by separate deployer container

set -e

REPOSITORY_NAME=${1:-$WEBHOOK_REPOSITORY_NAME}
REF=${2:-$WEBHOOK_REF}
COMMIT_SHA=${WEBHOOK_COMMIT_SHA:-"unknown"}
PUSHER_NAME=${WEBHOOK_PUSHER_NAME:-"unknown"}
BRANCH=${WEBHOOK_BRANCH:-$REF}

# Repository URLs
REPOSITORY_CLONE_URL=${WEBHOOK_REPOSITORY_CLONE_URL:-""}
REPOSITORY_SSH_URL=${WEBHOOK_REPOSITORY_SSH_URL:-""}

# Extract branch name from refs/heads/branch-name
BRANCH_NAME=$(echo "$BRANCH" | sed 's|refs/heads/||')

# Configuration
QUEUE_DIR="/queue"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WEBHOOK] $1"
}

# Validate required parameters
if [ -z "$REPOSITORY_NAME" ] || [ -z "$REF" ]; then
    log "ERROR: Missing required parameters (repository_name or ref)"
    exit 1
fi

# Check if branch is supported
case "$BRANCH_NAME" in
    main|master|staging|develop)
        log "✅ Branch '$BRANCH_NAME' is supported for deployment"
        ;;
    *)
        log "❌ Branch '$BRANCH_NAME' is not supported for deployment"
        exit 0
        ;;
esac

# Determine environment based on branch
case "$BRANCH_NAME" in
    main|master) ENVIRONMENT="production" ;;
    staging) ENVIRONMENT="staging" ;;
    develop) ENVIRONMENT="development" ;;
esac

log "📦 Queueing deployment request:"
log "Repository: $REPOSITORY_NAME"
log "Branch: $BRANCH_NAME → Environment: $ENVIRONMENT"
log "Commit: $COMMIT_SHA"
log "Pushed by: $PUSHER_NAME"

# Ensure queue directory exists
mkdir -p "$QUEUE_DIR"

# Create deployment request file with atomic write
TIMESTAMP=$(date +%s)
REQUEST_ID="${REPOSITORY_NAME}_${ENVIRONMENT}_${TIMESTAMP}"
TEMP_FILE="$QUEUE_DIR/.${REQUEST_ID}.tmp"
REQUEST_FILE="$QUEUE_DIR/${REQUEST_ID}.json"

# Write to temporary file first, then move (atomic operation)
cat > "$TEMP_FILE" << EOF
{
  "id": "$REQUEST_ID",
  "timestamp": "$TIMESTAMP",
  "created_at": "$(date -Iseconds)",
  "repository": "$REPOSITORY_NAME",
  "branch": "$BRANCH_NAME",
  "ref": "$REF",
  "environment": "$ENVIRONMENT",
  "commit_sha": "$COMMIT_SHA",
  "pusher_name": "$PUSHER_NAME",
  "repository_clone_url": "$REPOSITORY_CLONE_URL",
  "repository_ssh_url": "$REPOSITORY_SSH_URL",
  "status": "queued"
}
EOF

# Atomic move to final location (prevents partial reads)
mv "$TEMP_FILE" "$REQUEST_FILE"

log "✅ Deployment request queued: $(basename "$REQUEST_FILE")"
log "🔄 Deployer container will process the request"

# Output metrics for monitoring
echo "METRICS: deployment_queued{project=\"$REPOSITORY_NAME\",environment=\"$ENVIRONMENT\",commit=\"$COMMIT_SHA\",branch=\"$BRANCH_NAME\",pusher=\"$PUSHER_NAME\"} $(date +%s)"

exit 0