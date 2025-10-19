#!/bin/sh

# Webhook Dispatcher (POSIX sh compatible)
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

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DISPATCHER] $1"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if branch is supported (using case instead of arrays)
is_branch_supported() {
    local branch=$1
    case "$branch" in
        main|master|staging|develop)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get environment from branch (using case instead of associative array)
get_environment_for_branch() {
    local branch=$1
    case "$branch" in
        main|master)
            echo "production"
            ;;
        staging)
            echo "staging"
            ;;
        develop)
            echo "development"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Determine repository clone URL
get_repository_url() {
    # Check if SSH keys are available for private repositories
    local has_ssh_keys=false
    if [ -d "/root/.ssh-keys" ] && ([ -f "/root/.ssh-keys/id_rsa" ] || [ -f "/root/.ssh-keys/id_ed25519" ]); then
        has_ssh_keys=true
    fi
    
    # Priority order: SSH URL when keys available > HTTPS URL > fallback construction
    if [ "$has_ssh_keys" = true ] && [ -n "$REPOSITORY_SSH_URL" ]; then
        log "Using SSH URL for private repository (SSH keys available)"
        echo "$REPOSITORY_SSH_URL"
    elif [ -n "$REPOSITORY_CLONE_URL" ]; then
        echo "$REPOSITORY_CLONE_URL"
    elif [ -n "$REPOSITORY_SSH_URL" ]; then
        echo "$REPOSITORY_SSH_URL"
    else
        # Fallback to GitHub (for backward compatibility)
        log "Warning: No repository URL in webhook payload, falling back to GitHub"
        echo "https://github.com/Interops-io/${REPOSITORY_NAME}.git"
    fi
}

# Clone repository using docker run (so we don't need git in webhook container)
clone_repository_with_docker() {
    local repo_url=$1
    local branch=$2
    local target_dir=$3
    
    log "Cloning repository using Docker: $repo_url (branch: $branch)"
    
    # Remove existing directory
    rm -rf "$target_dir"
    
    # Check if we have SSH keys available for private repositories
    local ssh_volume_args=""
    if [ -d "/root/.ssh-keys" ] && [ -f "/root/.ssh-keys/id_rsa" ]; then
        log "Using SSH key for private repository access"
        ssh_volume_args="-v /root/.ssh-keys:/root/.ssh:ro"
    elif [ -d "/root/.ssh-keys" ] && [ -f "/root/.ssh-keys/id_ed25519" ]; then
        log "Using Ed25519 SSH key for private repository access"
        ssh_volume_args="-v /root/.ssh-keys:/root/.ssh:ro"
    else
        log "No SSH keys found, proceeding with public repository access or HTTPS with token"
    fi
    
    # Use alpine/git image to clone the repository
    # Mount the parent directory so we can write to the target
    local parent_dir=$(dirname "$(pwd)/$target_dir")
    local target_name=$(basename "$target_dir")
    
    if [ -n "$ssh_volume_args" ]; then
        # With SSH keys
        if docker run --rm \
            -v "$parent_dir:/workspace" \
            -w /workspace \
            $ssh_volume_args \
            -e GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
            alpine/git clone --branch "$branch" --depth 1 "$repo_url" "$target_name"; then
            log "✅ Repository cloned successfully with SSH"
            return 0
        else
            log "❌ Failed to clone repository with SSH. Check SSH key permissions and repository access."
            return 1
        fi
    else
        # Without SSH keys (public repos or HTTPS with tokens)
        if docker run --rm \
            -v "$parent_dir:/workspace" \
            -w /workspace \
            alpine/git clone --branch "$branch" --depth 1 "$repo_url" "$target_name"; then
            log "✅ Repository cloned successfully"
            return 0
        else
            log "❌ Failed to clone repository. Check repository URL, branch name, and access permissions."
            log "Repository URL: $repo_url"
            log "Branch: $branch"
            return 1
        fi
    fi
}

# Validate inputs
if [ -z "$REPOSITORY_NAME" ]; then
    error_exit "Repository name is required"
fi

if ! is_branch_supported "$BRANCH_NAME"; then
    log "Branch '$BRANCH_NAME' is not in the supported branches list: main, master, staging, develop"
    log "Skipping deployment for unsupported branch"
    exit 0
fi

# Get environment name from branch
ENVIRONMENT=$(get_environment_for_branch "$BRANCH_NAME")
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

# Load environment variables from project configuration
# 1. Base project .env (lowest priority)
# 2. Environment-specific .env (highest priority)

if [ -f "$BASE_PROJECT_DIR/.env" ]; then
    log "Loading base project .env file"
    set -a  # automatically export all variables
    . "$BASE_PROJECT_DIR/.env"
    set +a
fi

if [ -f "$PROJECT_DIR/.env" ]; then
    log "Loading environment-specific .env file"
    set -a
    . "$PROJECT_DIR/.env"
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
                    chmod +x "$hook_file" 2>/dev/null || log "Warning: Could not make $hook_file executable"
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
                chmod +x "$general_hook" 2>/dev/null || log "Warning: Could not make $general_hook executable"
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

# Standard deployment process
log "=== MAIN DEPLOYMENT ==="

# Check for docker-compose.yml first
if [ ! -f "$PROJECT_DIR/docker-compose.yml" ]; then
    error_exit "No docker-compose.yml found in project directory: $PROJECT_DIR"
fi

log "Found docker-compose.yml, starting deployment"
cd "$PROJECT_DIR" || error_exit "Failed to enter project directory: $PROJECT_DIR"

# Clone/update app source code for build context
log "Preparing app source code..."

# Get repository URL dynamically
repo_url=$(get_repository_url)

# Clone the app repository using Docker
log "Cloning app repository: $REPOSITORY_NAME (branch: $BRANCH_NAME)"
log "Repository URL: $repo_url"

if ! clone_repository_with_docker "$repo_url" "$BRANCH_NAME" "source"; then
    error_exit "Failed to clone repository $repo_url (branch: $BRANCH_NAME)"
fi

log "✅ App source prepared"

# Execute PRE-DEPLOY hooks (after cloning, closer to actual deployment)
log "=== PRE-DEPLOY HOOKS ==="
execute_hooks "pre_deploy" "pre-deploy"

# Standard Docker Compose deployment
log "Starting Docker Compose deployment..."
docker compose pull
docker compose build --pull
docker compose up -d

# Record successful deployment metrics for Grafana
echo "deployment_completed{project=\"$REPOSITORY_NAME\",environment=\"$ENVIRONMENT\",commit=\"$COMMIT_SHA\",branch=\"$BRANCH_NAME\",pusher=\"$PUSHER_NAME\"} $(date +%s)" > "/tmp/deployment_metrics_$$_$(date +%s).prom"
# Also log to stdout for debugging
echo "METRICS: deployment_completed{project=\"$REPOSITORY_NAME\",environment=\"$ENVIRONMENT\",commit=\"$COMMIT_SHA\",branch=\"$BRANCH_NAME\",pusher=\"$PUSHER_NAME\"} $(date +%s)"

log "✅ Main deployment completed"

# Execute POST-DEPLOY hooks
log "=== POST-DEPLOY HOOKS ==="
execute_hooks "post_deploy" "post-deploy"

# Cleanup old images
log "Cleaning up old Docker images..."
docker image prune -f

log "=== Webhook Dispatcher Completed ==="