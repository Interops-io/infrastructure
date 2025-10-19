#!/bin/bash

# Webhook Dispatcher (Bash)
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
        log "Using SSH URL for private repository (SSH keys available)" >&2
        echo "$REPOSITORY_SSH_URL"
    elif [ -n "$REPOSITORY_CLONE_URL" ]; then
        echo "$REPOSITORY_CLONE_URL"
    elif [ -n "$REPOSITORY_SSH_URL" ]; then
        echo "$REPOSITORY_SSH_URL"
    fi
}

# Clone repository using docker run (so we don't need git in webhook container)
clone_repository_with_docker() {
    local repo_url=$1
    local branch=$2
    local target_dir=$3
    
    log "Cloning repository using Docker: $repo_url (branch: $branch)"
    
    # Check if we have SSH keys available for private repositories
    # We need to mount the SSH keys from the host path, not from the container path
    local ssh_volume_args=""
    if [ -d "/root/.ssh-keys" ] && [ -f "/root/.ssh-keys/id_rsa" ]; then
        log "Using SSH key for private repository access"
        # Mount the same volume that's mounted to this container
        ssh_volume_args="--volumes-from $(hostname)"
    elif [ -d "/root/.ssh-keys" ] && [ -f "/root/.ssh-keys/id_ed25519" ]; then
        log "Using Ed25519 SSH key for private repository access"
        # Mount the same volume that's mounted to this container
        ssh_volume_args="--volumes-from $(hostname)"
    else
        log "No SSH keys found, proceeding with public repository access or HTTPS with token"
    fi
    
    # Use alpine/git image to clone the repository
    # Use --volumes-from to inherit the same volume mounts as this container
    # This way alpine/git will see the same /projects mount as the deployer container
    local target_name=$(basename "$target_dir")
    local container_hostname=$(hostname)
    
    log "Debug paths:"
    log "  Current dir: $(pwd)"
    log "  Target dir: $target_dir"
    log "  Target name: $target_name"
    log "  Container hostname: $container_hostname"
    log "  Full target path: $(pwd)/$target_dir"
    
    if [ -n "$ssh_volume_args" ]; then
        # With SSH keys - explicitly specify which key to use
        # Note: Using --volumes-from so keys stay at /root/.ssh-keys/ in alpine/git container too
        local ssh_key_path=""
        if [ -f "/root/.ssh-keys/id_ed25519" ]; then
            ssh_key_path="/root/.ssh-keys/id_ed25519"
        elif [ -f "/root/.ssh-keys/id_rsa" ]; then
            ssh_key_path="/root/.ssh-keys/id_rsa"
        fi
        

        
        # Check and remove directory inside the alpine/git container before cloning
        log "Checking for existing directory in alpine/git workspace..."
        docker run --rm \
            --volumes-from "$container_hostname" \
            -w "$(pwd)" \
            --entrypoint sh \
            alpine/git -c "if [ -d '$target_name' ]; then echo 'Removing existing $target_name directory in container'; rm -rf '$target_name'; else echo 'No existing $target_name directory in container'; fi"
        
        if docker run --rm \
            --volumes-from "$container_hostname" \
            -w "$(pwd)" \
            -e GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $ssh_key_path" \
            alpine/git clone --branch "$branch" --depth 1 "$repo_url" "$target_name"; then
            log "✅ Repository cloned successfully with SSH key: $ssh_key_path"
            return 0
        else
            log "❌ Failed to clone repository with SSH. Check SSH key permissions and repository access."
            return 1
        fi
    else
        # Without SSH keys (public repos or HTTPS with tokens)
        if docker run --rm \
            --volumes-from "$container_hostname" \
            -w "$(pwd)" \
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

# Set common Docker Compose variables that projects typically need
export PROJECT_NAME="${PROJECT_NAME:-$REPOSITORY_NAME}"
export suffix="${suffix:-$ENVIRONMENT}"

log "Environment variables set:"
log "  PROJECT_NAME=$PROJECT_NAME"
log "  suffix=$suffix"
log "  REPOSITORY_NAME=$REPOSITORY_NAME"
log "  ENVIRONMENT=$ENVIRONMENT"

# Function to execute hooks
execute_hooks() {
    local hook_pattern=$1
    local hook_stage=$2
    
    # Build prioritized list of service hooks (environment-specific overrides base)
    declare -A service_hooks
    declare -A hook_sources
    
    # First, collect hooks from base project directory (lower priority)
    if [ -d "$BASE_PROJECT_DIR" ]; then
        for hook_file in "$BASE_PROJECT_DIR"/${hook_pattern}.*.sh; do
            if [ -f "$hook_file" ]; then
                local service_name=$(echo "$hook_file" | sed "s/.*${hook_pattern}\.\(.*\)\.sh/\1/")
                service_hooks["$service_name"]="$hook_file"
                hook_sources["$service_name"]="base"
            fi
        done
    fi
    
    # Then, collect hooks from environment directory (higher priority - overrides base)
    if [ -d "$PROJECT_DIR" ]; then
        for hook_file in "$PROJECT_DIR"/${hook_pattern}.*.sh; do
            if [ -f "$hook_file" ]; then
                local service_name=$(echo "$hook_file" | sed "s/.*${hook_pattern}\.\(.*\)\.sh/\1/")
                service_hooks["$service_name"]="$hook_file"
                hook_sources["$service_name"]="$ENVIRONMENT"
            fi
        done
    fi
    
    # Execute prioritized service hooks
    for service_name in "${!service_hooks[@]}"; do
        local hook_file="${service_hooks[$service_name]}"
        local source="${hook_sources[$service_name]}"
        local hook_dir=$(dirname "$hook_file")
        
        log "Executing $hook_stage hook for service '$service_name': $(basename "$hook_file") (from $source)"
        chmod +x "$hook_file" 2>/dev/null || log "Warning: Could not make $hook_file executable"
        cd "$hook_dir" || { log "ERROR: Failed to enter directory $hook_dir"; continue; }
        
        # Execute service-specific hooks inside their respective containers
        local script_name=$(basename "$hook_file")
        local container_script_path="/tmp/$script_name"
        
        if docker compose cp "$script_name" "$service_name:$container_script_path" 2>/dev/null; then
            log "Running $script_name inside $service_name container"
            if docker compose exec -T "$service_name" chmod +x "$container_script_path" && \
               docker compose exec -T "$service_name" bash -c "cd /var/www/html 2>/dev/null || cd /; $container_script_path"; then
                log "✅ $hook_stage hook for '$service_name' completed successfully"
            else
                log "⚠️ $hook_stage hook for '$service_name' failed (continuing anyway)"
            fi
        else
            log "⚠️ Could not copy $script_name to $service_name container, running on deployer instead"
            # Fallback to running on deployer container
            if ./"$script_name"; then
                log "✅ $hook_stage hook for '$service_name' completed successfully (fallback)"
            else
                log "⚠️ $hook_stage hook for '$service_name' failed (continuing anyway)"
            fi
        fi
    done
    
    # Execute general hook with environment-specific prioritization
    local general_hook=""
    local general_source=""
    
    # Check base project directory first (lower priority)
    if [ -f "$BASE_PROJECT_DIR/${hook_pattern}.sh" ]; then
        general_hook="$BASE_PROJECT_DIR/${hook_pattern}.sh"
        general_source="base"
    fi
    
    # Check environment directory (higher priority - overrides base)
    if [ -f "$PROJECT_DIR/${hook_pattern}.sh" ]; then
        general_hook="$PROJECT_DIR/${hook_pattern}.sh"
        general_source="$ENVIRONMENT"
    fi
    
    # Execute the prioritized general hook
    if [ -n "$general_hook" ]; then
        local hook_dir=$(dirname "$general_hook")
        log "Executing general $hook_stage hook: $(basename "$general_hook") (from $general_source)"
        chmod +x "$general_hook" 2>/dev/null || log "Warning: Could not make $general_hook executable"
        cd "$hook_dir" || { log "ERROR: Failed to enter directory $hook_dir"; return 1; }
        if ./"$(basename "$general_hook")"; then
            log "✅ General $hook_stage hook completed successfully"
        else
            log "⚠️ General $hook_stage hook failed (continuing anyway)"
        fi
    fi
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

# Ensure we're back in the project directory after hooks
cd "$PROJECT_DIR" || error_exit "Failed to return to project directory: $PROJECT_DIR"

# Export Docker Compose variables right before deployment
PROJECT_NAME="${PROJECT_NAME:-$REPOSITORY_NAME}"
suffix="${suffix:-$ENVIRONMENT}"
export PROJECT_NAME
export suffix

log "Final environment variables for Docker Compose:"
log "  PROJECT_NAME=$PROJECT_NAME"
log "  suffix=$suffix"

# Verify the variables are actually exported
env | grep -E "^(PROJECT_NAME|suffix)=" || log "Warning: PROJECT_NAME or suffix not found in environment"

# Standard Docker Compose deployment
log "Starting Docker Compose deployment..."
log "Current directory: $(pwd)"

# Debug environment variables right before Docker Compose
log "Environment check before Docker Compose:"
log "  PROJECT_NAME=${PROJECT_NAME:-UNSET}"
log "  suffix=${suffix:-UNSET}"
log "  REPOSITORY_NAME=${REPOSITORY_NAME:-UNSET}"
log "  ENVIRONMENT=${ENVIRONMENT:-UNSET}"

log "Files in current directory:"
ls -la
log "Looking for docker-compose.yml..."
if [ -f "docker-compose.yml" ]; then
    log "✅ docker-compose.yml found"
else
    log "❌ docker-compose.yml not found in $(pwd)"
fi

docker compose pull
docker compose build --pull
docker compose up -d --force-recreate

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