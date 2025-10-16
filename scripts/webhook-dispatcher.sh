#!/bin/bash

# Webhook Dispatcher
# Finds and runs the correct deploy script for each project

set -e

REPOSITORY_NAME=${1:-$WEBHOOK_REPOSITORY_NAME}
REF=${2:-$WEBHOOK_REF}
COMMIT_SHA=${WEBHOOK_COMMIT_SHA:-"unknown"}
PUSHER_NAME=${WEBHOOK_PUSHER_NAME:-"unknown"}
BRANCH=${WEBHOOK_BRANCH:-$REF}

# Repository URLs - try to get from webhook payload
REPOSITORY_CLONE_URL=${WEBHOOK_REPOSITORY_CLONE_URL:-""}
REPOSITORY_SSH_URL=${WEBHOOK_REPOSITORY_SSH_URL:-""}

# Extract branch name from refs/heads/branch-name
BRANCH_NAME=$(echo "$BRANCH" | sed 's|refs/heads/||')

# Configuration
PROJECTS_DIR="/projects"
LOG_FILE="/var/log/webhook/dispatcher.log"

# Supported branches (whitelist)
SUPPORTED_BRANCHES=("main" "master" "staging" "develop")

# Branch to environment mapping
declare -A BRANCH_ENV_MAP
BRANCH_ENV_MAP["main"]="production"
BRANCH_ENV_MAP["master"]="production"
BRANCH_ENV_MAP["staging"]="staging"
BRANCH_ENV_MAP["develop"]="development"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DISPATCHER] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Determine repository clone URL
get_repository_url() {
    # Priority order: webhook provided URLs > fallback construction
    if [ -n "$REPOSITORY_CLONE_URL" ]; then
        echo "$REPOSITORY_CLONE_URL"
    elif [ -n "$REPOSITORY_SSH_URL" ]; then
        echo "$REPOSITORY_SSH_URL"
    else
        # Fallback to GitHub (for backward compatibility)
        log "Warning: No repository URL in webhook payload, falling back to GitHub"
        echo "https://github.com/Interops-io/${REPOSITORY_NAME}.git"
    fi
}

# Validate inputs
if [ -z "$REPOSITORY_NAME" ]; then
    error_exit "Repository name is required"
fi

# Check if branch is supported
is_branch_supported() {
    local branch=$1
    for supported in "${SUPPORTED_BRANCHES[@]}"; do
        if [[ "$branch" == "$supported" ]]; then
            return 0
        fi
    done
    return 1
}

if ! is_branch_supported "$BRANCH_NAME"; then
    log "Branch '$BRANCH_NAME' is not in the supported branches list: ${SUPPORTED_BRANCHES[*]}"
    log "Skipping deployment for unsupported branch"
    exit 0
fi

# Get environment name from branch
ENVIRONMENT=${BRANCH_ENV_MAP[$BRANCH_NAME]}
if [ -z "$ENVIRONMENT" ]; then
    error_exit "No environment mapping found for branch: $BRANCH_NAME"
fi

log "=== Webhook Dispatcher Started ==="
log "Repository: $REPOSITORY_NAME"
log "Ref: $REF"
log "Branch: $BRANCH_NAME"
log "Environment: $ENVIRONMENT"
log "Commit: $COMMIT_SHA"
log "Pushed by: $PUSHER_NAME"
log "Clone URL: $REPOSITORY_CLONE_URL"

# Find project directory with environment subdirectory
BASE_PROJECT_DIR="$PROJECTS_DIR/$REPOSITORY_NAME"
PROJECT_DIR="$BASE_PROJECT_DIR/$ENVIRONMENT"

if [ ! -d "$BASE_PROJECT_DIR" ]; then
    error_exit "Base project directory $BASE_PROJECT_DIR does not exist"
fi

if [ ! -d "$PROJECT_DIR" ]; then
    error_exit "Environment directory $PROJECT_DIR does not exist"
fi

log "Found base project directory: $BASE_PROJECT_DIR"
log "Found environment directory: $PROJECT_DIR"

# Setup database credentials if needed
log "Checking database setup for $REPOSITORY_NAME ($ENVIRONMENT)"
if [ -f "$PROJECT_DIR/.env.database" ]; then
    # Check if .env.database has credentials
    if grep -q "DB_PASSWORD=" "$PROJECT_DIR/.env.database" 2>/dev/null; then
        log "Database credentials already configured"
    else
        log "Database configuration needed, ensuring database setup..."
        # Run database setup script (relative path - both scripts in same directory)
        ./setup-database.sh setup "$BASE_PROJECT_DIR" "$ENVIRONMENT" || log "Warning: Database setup failed or skipped"
    fi
fi

# Load environment variables in order of precedence:
# 1. Base project .env (lowest priority)
# 2. Environment-specific .env (highest priority - may now include auto-generated DB credentials)

if [ -f "$BASE_PROJECT_DIR/.env" ]; then
    log "Loading base project .env file"
    set -a  # automatically export all variables
    source "$BASE_PROJECT_DIR/.env"
    set +a
fi

if [ -f "$PROJECT_DIR/.env" ]; then
    log "Loading environment-specific .env file"
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# Set up environment for hooks and deployment
export REPOSITORY_NAME
export REF
export COMMIT_SHA
export PUSHER_NAME
export BRANCH
export BRANCH_NAME
export ENVIRONMENT
export PROJECT_DIR
export BASE_PROJECT_DIR
export PROJECTS_DIR
export BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Function to execute hooks
execute_hooks() {
    local hook_pattern=$1
    local hook_stage=$2
    
    # Look for hooks in both base and environment directories
    for hook_dir in "$BASE_PROJECT_DIR" "$PROJECT_DIR"; do
        if [ -d "$hook_dir" ]; then
            # Execute specific service hooks (e.g., pre_deploy.app.sh, post_deploy.redis.sh)
            for hook_file in "$hook_dir"/${hook_pattern}.*.sh; do
                if [ -f "$hook_file" ]; then
                    local service_name=$(echo "$hook_file" | sed "s/.*${hook_pattern}\.\(.*\)\.sh/\1/")
                    log "Executing $hook_stage hook for service '$service_name': $(basename "$hook_file")"
                    chmod +x "$hook_file"
                    cd "$hook_dir" || { log "ERROR: Failed to enter directory $hook_dir"; continue; }
                    if ./"$(basename "$hook_file")"; then
                        log "✅ $hook_stage hook for '$service_name' completed successfully"
                    else
                        log "⚠️ $hook_stage hook for '$service_name' failed (continuing anyway)"
                    fi
                fi
            done
            
            # Execute general hook (e.g., pre_deploy.sh, post_deploy.sh)
            local general_hook="$hook_dir/${hook_pattern}.sh"
            if [ -f "$general_hook" ]; then
                log "Executing general $hook_stage hook: $(basename "$general_hook")"
                chmod +x "$general_hook"
                cd "$hook_dir" || { log "ERROR: Failed to enter directory $hook_dir"; return 1; }
                if ./"$(basename "$general_hook")"; then
                    log "✅ General $hook_stage hook completed successfully"
                else
                    log "⚠️ General $hook_stage hook failed (continuing anyway)"
                fi
            fi
        fi
    done
}

# Execute PRE-DEPLOY hooks
log "=== PRE-DEPLOY HOOKS ==="
execute_hooks "pre_deploy" "pre-deploy"

# Standard deployment process
log "=== MAIN DEPLOYMENT ==="
if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    log "Found docker-compose.yml, starting deployment"
    
    cd "$PROJECT_DIR" || error_exit "Failed to enter project directory: $PROJECT_DIR"
    
    # Clone/update app source code for build context
    log "Preparing app source code..."
    
    # Remove existing source if it exists
    rm -rf source
    
    # Get repository URL dynamically
    local repo_url=$(get_repository_url)
    
    # Clone the app repository
    log "Cloning app repository: $REPOSITORY_NAME (branch: $BRANCH_NAME)"
    log "Repository URL: $repo_url"
    
    if ! git clone --branch "$BRANCH_NAME" --depth 1 "$repo_url" source; then
        error_exit "Failed to clone repository $repo_url (branch: $BRANCH_NAME)"
    fi
    
    log "✅ App source prepared"
    
    # Standard Docker Compose deployment
    log "Starting Docker Compose deployment..."
    docker compose pull
    docker compose build --pull
    docker compose up -d
    
    # Record successful deployment metrics for Grafana
    echo "deployment_completed{project=\"$REPOSITORY_NAME\",environment=\"$ENVIRONMENT\",commit=\"$COMMIT_SHA\",branch=\"$BRANCH_NAME\",pusher=\"$PUSHER_NAME\"} $(date +%s)" > "/tmp/deployment_metrics_$$_$(date +%s).prom"
    
    log "✅ Main deployment completed"
else
    error_exit "No docker-compose.yml found in project directory: $PROJECT_DIR"
fi

# Execute POST-DEPLOY hooks
log "=== POST-DEPLOY HOOKS ==="
execute_hooks "post_deploy" "post-deploy"

# Cleanup old images
log "Cleaning up old Docker images..."
docker image prune -f

log "=== Webhook Dispatcher Completed ==="